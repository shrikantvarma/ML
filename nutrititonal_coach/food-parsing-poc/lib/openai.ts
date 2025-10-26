import OpenAI from 'openai'
import { z } from 'zod'

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

// Schema for parsed food item with nutrition
const FoodItemWithNutritionSchema = z.object({
  foodName: z.string().describe('The name of the food item (lowercase, singular)'),
  quantity: z.number().describe('The quantity/amount consumed'),
  unit: z.string().describe('The unit of measurement (e.g., piece, cup, tbsp, g, ml)'),
  // Calculated nutrition for the specific quantity consumed
  calories: z.number().describe('Total calories for this food item'),
  protein: z.number().describe('Total protein in grams'),
  carbs: z.number().describe('Total carbohydrates in grams'),
  fat: z.number().describe('Total fat in grams'),
  fiber: z.number().describe('Total fiber in grams'),
  confidence: z.number().min(0).max(100).describe('Confidence in the nutrition calculation (0-100)'),
})

const ParsedFoodsWithNutritionSchema = z.object({
  foods: z.array(FoodItemWithNutritionSchema),
})

const ParsedFoodItemSchema = z.object({
  foodName: z.string().trim().min(1).transform(value => value.toLowerCase()),
  quantity: z.coerce.number(),
  unit: z.string().trim().min(1).transform(value => value.toLowerCase()),
})

const ParsedFoodsSchema = z.object({
  foods: z.array(ParsedFoodItemSchema),
})

export type FoodItemWithNutrition = z.infer<typeof FoodItemWithNutritionSchema>
export type ParsedFoodsWithNutrition = z.infer<typeof ParsedFoodsWithNutritionSchema>
export type ParsedFoodItem = z.infer<typeof ParsedFoodItemSchema>

/**
 * Parse natural language food input using OpenAI
 * Example: "2 eggs, 1 chai, 3 egg whites" -> [{foodName: "whole egg", quantity: 2, unit: "piece"}, ...]
 */
export async function parseFoodInput(input: string): Promise<ParsedFoodItem[]> {
  try {
    const systemPrompt = `You are a food parsing assistant for a nutrition tracking app. Your job is to extract individual food items, quantities, and units from natural language input.

Guidelines:
1. Convert food names to lowercase, singular form
2. Standardize common names:
   - "egg" or "whole egg" for regular eggs
   - "egg white" or "white" for egg whites
   - "greek yogurt" for yogurt
   - "chia seeds" for chia
   - "barebells protein bar" or "barebells bar" for protein bars
3. Infer units when not specified:
   - eggs: "piece"
   - chai/coffee: "cup"
   - yogurt/milk: "cup" (unless specified as grams)
   - seeds: "tbsp" (unless specified)
   - nuts: "piece" or "handful"
4. Convert common abbreviations:
   - "tbsp" for tablespoon
   - "tsp" for teaspoon
   - "g" for grams
   - "ml" for milliliters
5. Handle Indian English variations:
   - "1 chai" = 1 cup of chai tea
   - "1 roti" = 1 piece roti
   - "dal" = lentils/dal

Return a JSON object with an array of foods, each containing: foodName, quantity, and unit.`

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: `Parse this food input: "${input}"`,
        },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.2, // Low temperature for consistent parsing
    })

    const responseContent = completion.choices[0]?.message?.content

    if (!responseContent) {
      throw new Error('No response from OpenAI')
    }

    // Parse and validate the response
    const parsed = JSON.parse(responseContent)
    const validated = ParsedFoodsSchema.parse(parsed)

    return validated.foods
  } catch (error) {
    console.error('Error parsing food input:', error)
    throw new Error(
      `Failed to parse food input: ${error instanceof Error ? error.message : 'Unknown error'}`
    )
  }
}

/**
 * ONE-SHOT: Parse food input AND calculate nutrition in a single OpenAI call
 * This is the new recommended approach - OpenAI handles everything including unit conversions
 */
export async function parseFoodWithNutrition(input: string): Promise<FoodItemWithNutrition[]> {
  try {
    const systemPrompt = `You are an intelligent nutrition calculator and food parser. Your job is to:
1. Parse natural language food descriptions
2. Calculate accurate nutrition data for the EXACT quantity specified
3. Handle all unit conversions automatically

Guidelines:
- For each food item, calculate the TOTAL macros for the quantity consumed (not per 100g)
- Example: "2 eggs" should return calories/protein for 2 eggs, not 1 egg
- Example: "1 cup Greek yogurt" should calculate macros for 1 cup (≈245g), not 100g
- Handle unit conversions intelligently:
  * 1 cup Greek yogurt ≈ 245g
  * 1 tbsp chia seeds ≈ 12g
  * 1 whole egg ≈ 50g
  * 1 egg white ≈ 30g
  * 1 cup chai (with milk) ≈ 240ml

- Standardize food names (lowercase, singular):
  * "egg" or "whole egg" for regular eggs
  * "egg white" for whites
  * "greek yogurt" for yogurt
  * "chia seeds" for chia

- Assign confidence scores:
  * 90-100: You know the exact food and portion
  * 70-89: Good estimate based on typical values
  * 50-69: Rough estimate, significant uncertainty
  * <50: Very uncertain

Return JSON with an array of foods, each containing:
- foodName (string)
- quantity (number)
- unit (string)
- calories (number): TOTAL calories for this quantity
- protein (number): TOTAL protein in grams
- carbs (number): TOTAL carbs in grams
- fat (number): TOTAL fat in grams
- fiber (number): TOTAL fiber in grams
- confidence (number): 0-100`

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: `Parse this food input and calculate nutrition: "${input}"`,
        },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.3, // Slightly higher for better estimation
    })

    const responseContent = completion.choices[0]?.message?.content

    if (!responseContent) {
      throw new Error('No response from OpenAI')
    }

    // Parse and validate the response
    const parsed = JSON.parse(responseContent)
    const validated = ParsedFoodsWithNutritionSchema.parse(parsed)

    return validated.foods
  } catch (error) {
    console.error('Error parsing food with nutrition:', error)
    throw new Error(
      `Failed to parse food with nutrition: ${error instanceof Error ? error.message : 'Unknown error'}`
    )
  }
}

/**
 * Test function to validate parsing accuracy
 */
export async function testFoodParsing() {
  const testCases = [
    '2 eggs, 1 chai, 3 egg whites',
    '1 cup Greek yogurt with 1 tbsp chia seeds',
    'Breakfast: 2 rotis, 1 cup dal, and a chai',
    'Half barebells bar and a handful of almonds',
    '100g paneer, 1 cup rice',
  ]

  console.log('🧪 Testing food parsing...\n')

  for (const testCase of testCases) {
    console.log(`Input: "${testCase}"`)
    try {
      const result = await parseFoodInput(testCase)
      console.log('Parsed:', JSON.stringify(result, null, 2))
    } catch (error) {
      console.error('Error:', error)
    }
    console.log('---\n')
  }
}
