import { prisma } from './prisma'
import type { ParsedFoodItem } from './openai'
import * as levenshtein from 'fast-levenshtein'

export interface NutritionData {
  foodId: string | null
  foodName: string
  quantity: number
  unit: string
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
  matched: boolean // Whether we found a match in the database
  confidence?: number // 0-100, confidence in the match
  suggestedName?: string // If fuzzy matched, what we actually matched to
}

export interface MealNutrition {
  foods: NutritionData[]
  totals: {
    calories: number
    protein: number
    carbs: number
    fat: number
    fiber: number
  }
}

/**
 * Normalize food name for matching
 * Removes apostrophes, extra spaces, makes lowercase
 */
function normalizeFoodName(name: string): string {
  return name
    .toLowerCase()
    .replace(/['\"]/g, '') // Remove apostrophes and quotes
    .replace(/\s+/g, ' ') // Normalize spaces
    .trim()
}

interface FoodMatch {
  food: any
  confidence: number
  matchType: 'exact' | 'normalized' | 'levenshtein' | 'substring'
}

/**
 * Enhanced fuzzy match food name against database with confidence scoring
 * Multi-level matching:
 * - Level 1 (100%): Exact match
 * - Level 2 (90%): Normalized match (no apostrophes, case-insensitive)
 * - Level 3 (70-85%): Levenshtein distance ≤ 2
 * - Level 4 (50-70%): Partial substring match
 */
async function findFoodInDatabase(foodName: string): Promise<FoodMatch | null> {
  const searchNormalized = normalizeFoodName(foodName)

  // Get all foods from database
  const foods = await prisma.food.findMany()

  let bestMatch: FoodMatch | null = null

  for (const food of foods) {
    const dbNameNormalized = normalizeFoodName(food.name)

    // Level 1: Exact match
    if (food.name.toLowerCase() === foodName.toLowerCase()) {
      return { food, confidence: 100, matchType: 'exact' }
    }

    // Level 2: Normalized match
    if (dbNameNormalized === searchNormalized) {
      if (!bestMatch || bestMatch.confidence < 90) {
        bestMatch = { food, confidence: 90, matchType: 'normalized' }
      }
      continue
    }

    // Level 3: Levenshtein distance matching
    const distance = levenshtein.get(searchNormalized, dbNameNormalized)
    const maxLength = Math.max(searchNormalized.length, dbNameNormalized.length)
    const similarity = 1 - distance / maxLength

    if (distance <= 2 && distance < maxLength / 3) {
      // Allow up to 2 character edits and ensure it's not too different proportionally
      const confidence = Math.floor(70 + similarity * 15) // 70-85% confidence
      if (!bestMatch || bestMatch.confidence < confidence) {
        bestMatch = { food, confidence, matchType: 'levenshtein' }
      }
      continue
    }

    // Level 4: Substring matching
    if (
      dbNameNormalized.includes(searchNormalized) ||
      searchNormalized.includes(dbNameNormalized)
    ) {
      const confidence = Math.floor(50 + (searchNormalized.length / maxLength) * 20) // 50-70%
      if (!bestMatch || bestMatch.confidence < confidence) {
        bestMatch = { food, confidence, matchType: 'substring' }
      }
    }

    // Special case: Handle brand names
    if (food.brand && searchNormalized.includes(normalizeFoodName(food.brand))) {
      const confidence = 75
      if (!bestMatch || bestMatch.confidence < confidence) {
        bestMatch = { food, confidence, matchType: 'substring' }
      }
    }
  }

  return bestMatch
}

/**
 * Convert quantity from parsed unit to database unit
 * Example: If DB has "100g" but user said "1 cup", convert accordingly
 */
function convertUnit(
  quantity: number,
  fromUnit: string,
  toUnit: string,
  foodName: string
): number {
  // If units match, no conversion needed
  if (fromUnit.toLowerCase() === toUnit.toLowerCase()) {
    return quantity
  }

  // Common conversions
  const conversions: Record<string, Record<string, number>> = {
    // 1 cup = 237ml
    cup: {
      ml: 237,
      g: 240, // approximate for liquids/yogurt
    },
    // 1 tbsp = 15ml
    tbsp: {
      ml: 15,
      g: 15,
    },
    // 1 tsp = 5ml
    tsp: {
      ml: 5,
      g: 5,
    },
  }

  const fromLower = fromUnit.toLowerCase()
  const toLower = toUnit.toLowerCase()

  if (conversions[fromLower] && conversions[fromLower][toLower]) {
    return quantity * conversions[fromLower][toLower]
  }

  // If we can't convert, return the original quantity
  // This is acceptable for the POC as most items are already in compatible units
  console.warn(`Cannot convert ${fromUnit} to ${toUnit} for ${foodName}`)
  return quantity
}

/**
 * Calculate nutrition data for a parsed food item with confidence scoring
 */
export async function calculateNutrition(item: ParsedFoodItem): Promise<NutritionData> {
  const matchResult = await findFoodInDatabase(item.foodName)

  if (!matchResult) {
    // If food not found, return empty nutrition data
    console.warn(`Food "${item.foodName}" not found in database`)
    return {
      foodId: null,
      foodName: item.foodName,
      quantity: item.quantity,
      unit: item.unit,
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      fiber: 0,
      matched: false,
      confidence: 0,
    }
  }

  const { food, confidence, matchType } = matchResult

  // Convert quantity to match database serving size
  const convertedQuantity = convertUnit(
    item.quantity,
    item.unit,
    food.servingUnit,
    item.foodName
  )

  // Calculate multiplier based on serving size
  const servingSizeMultiplier = convertedQuantity / food.servingSize

  // Calculate macros
  const result: NutritionData = {
    foodId: food.id,
    foodName: food.name,
    quantity: item.quantity,
    unit: item.unit,
    calories: parseFloat((food.calories * servingSizeMultiplier).toFixed(1)),
    protein: parseFloat((food.protein * servingSizeMultiplier).toFixed(1)),
    carbs: parseFloat((food.carbs * servingSizeMultiplier).toFixed(1)),
    fat: parseFloat((food.fat * servingSizeMultiplier).toFixed(1)),
    fiber: parseFloat((food.fiber * servingSizeMultiplier).toFixed(1)),
    matched: true,
    confidence,
  }

  // If fuzzy matched (not exact), include what we actually matched to
  if (matchType !== 'exact' && food.name.toLowerCase() !== item.foodName.toLowerCase()) {
    result.suggestedName = food.name
  }

  console.log(
    `Matched "${item.foodName}" → "${food.name}" (${matchType}, ${confidence}% confidence)`
  )

  return result
}

/**
 * Calculate nutrition for multiple parsed food items (a meal)
 */
export async function calculateMealNutrition(
  parsedFoods: ParsedFoodItem[]
): Promise<MealNutrition> {
  const nutritionData = await Promise.all(parsedFoods.map(calculateNutrition))

  // Calculate totals
  const totals = nutritionData.reduce(
    (acc, food) => ({
      calories: acc.calories + food.calories,
      protein: acc.protein + food.protein,
      carbs: acc.carbs + food.carbs,
      fat: acc.fat + food.fat,
      fiber: acc.fiber + food.fiber,
    }),
    { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 }
  )

  // Round totals
  totals.calories = parseFloat(totals.calories.toFixed(1))
  totals.protein = parseFloat(totals.protein.toFixed(1))
  totals.carbs = parseFloat(totals.carbs.toFixed(1))
  totals.fat = parseFloat(totals.fat.toFixed(1))
  totals.fiber = parseFloat(totals.fiber.toFixed(1))

  return {
    foods: nutritionData,
    totals,
  }
}

/**
 * Save a meal to the database
 */
interface SaveMealInput {
  rawInput: string
  mealData: MealNutrition
  userId: string
  mealType?: string
}

export async function saveMeal({
  rawInput,
  mealData,
  userId,
  mealType,
}: SaveMealInput): Promise<{ id: string }> {
  const meal = await prisma.meal.create({
    data: {
      rawInput,
      mealType: mealType || null,
      userId,
      totalCalories: mealData.totals.calories,
      totalProtein: mealData.totals.protein,
      totalCarbs: mealData.totals.carbs,
      totalFat: mealData.totals.fat,
      totalFiber: mealData.totals.fiber,
      foods: {
        create: mealData.foods.map((food) => ({
          foodId: food.foodId,
          foodName: food.foodName,
          quantity: food.quantity,
          unit: food.unit,
          calories: food.calories,
          protein: food.protein,
          carbs: food.carbs,
          fat: food.fat,
          fiber: food.fiber,
        })),
      },
    },
    include: {
      foods: true,
    },
  })

  return { id: meal.id }
}
