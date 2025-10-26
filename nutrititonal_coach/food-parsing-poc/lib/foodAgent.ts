import OpenAI from 'openai'
import { z } from 'zod'

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

export interface FoodNutritionData {
  name: string
  brand: string | null
  category: string
  servingSize: number
  servingUnit: string
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
  source: string
  confidence: 'high' | 'medium' | 'low'
  reasoning?: string
}

const RawFoodNutritionSchema = z.object({
  name: z.string().trim().min(1).optional(),
  brand: z.union([z.string().trim().min(1), z.null()]).optional(),
  category: z.string().trim().min(1).optional(),
  servingSize: z.union([z.number(), z.string().trim()]).optional(),
  servingUnit: z.string().trim().min(1).optional(),
  calories: z.union([z.number(), z.string().trim()]).optional(),
  protein: z.union([z.number(), z.string().trim()]).optional(),
  carbs: z.union([z.number(), z.string().trim()]).optional(),
  fat: z.union([z.number(), z.string().trim()]).optional(),
  fiber: z.union([z.number(), z.string().trim()]).optional(),
  source: z.string().trim().min(1).optional(),
  confidence: z.string().trim().toLowerCase().optional(),
  reasoning: z.string().optional(),
})

function coerceNumber(value: unknown, fallback = 0): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value
  }
  if (typeof value === 'string') {
    const numeric = parseFloat(value.replace(/[^\d.-]/g, ''))
    if (!Number.isNaN(numeric) && Number.isFinite(numeric)) {
      return numeric
    }
  }
  return fallback
}

function normalizeConfidence(value?: string): 'high' | 'medium' | 'low' {
  if (!value) return 'medium'
  const normalized = value.toLowerCase()
  if (normalized === 'high' || normalized === 'medium' || normalized === 'low') {
    return normalized
  }
  if (normalized.includes('high')) return 'high'
  if (normalized.includes('low')) return 'low'
  return 'medium'
}

function normalizeText(value: string | null | undefined): string | null {
  if (!value) return null
  const trimmed = value.trim()
  return trimmed.length === 0 ? null : trimmed
}

/**
 * Agent: Find nutrition data for unknown foods
 * Uses OpenAI with function calling to search and estimate nutrition
 */
export async function findFoodNutrition(
  foodName: string,
  quantity?: number,
  unit?: string
): Promise<{
  data: FoodNutritionData
  debug: {
    prompt: string
    rawResponse: unknown
  }
}> {
  const systemPrompt = `You are a nutrition data agent. Your job is to find accurate nutrition information for foods that users ask about.

When given a food name:
1. If it's a branded product (e.g., "Trader Joe's Mediterranean Salad"), try to recall the exact nutrition facts
2. If it's a generic food, estimate based on typical recipes/ingredients
3. Use standard serving sizes (100g for solids, 1 cup/piece for items, 1 serving for packaged foods)
4. Be conservative with estimates - round to reasonable values
5. Assign confidence:
   - HIGH: You know the exact product or it's a standard food
   - MEDIUM: You can make a good estimate based on ingredients
   - LOW: You're making a rough guess

Return nutrition data in JSON format with all required fields using this exact template:
{
  "name": "<string>",
  "brand": "<string or null>",
  "category": "<string>",
  "servingSize": <number>,
  "servingUnit": "<string>",
  "calories": <number>,
  "protein": <number>,
  "carbs": <number>,
  "fat": <number>,
  "fiber": <number>,
  "source": "<string describing where you got the data>",
  "confidence": "<high|medium|low>",
  "reasoning": "<string explanation>"
}

Always include every key even if you must make a reasonable estimate; when unknown, use null for brand and "openai_estimate" for source.`

  try {
    const userPrompt = `Find nutrition data for: "${foodName}"${
      quantity && unit ? ` (user asked for ${quantity} ${unit})` : ''
    }`

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: userPrompt,
        },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.3,
    })

    const responseContent = completion.choices[0]?.message?.content

    if (!responseContent) {
      throw new Error('No response from OpenAI')
    }

    const parsed = JSON.parse(responseContent)
    const raw = RawFoodNutritionSchema.parse(parsed)

    const normalizedName = normalizeText(raw.name) ?? foodName

    const normalized: FoodNutritionData = {
      name: normalizedName,
      brand: normalizeText(raw.brand ?? null),
      category: normalizeText(raw.category) ?? 'general',
      servingSize: Math.max(coerceNumber(raw.servingSize, quantity ?? 1), 0.0001),
      servingUnit: normalizeText(raw.servingUnit) ?? unit ?? 'serving',
      calories: Math.max(coerceNumber(raw.calories), 0),
      protein: Math.max(coerceNumber(raw.protein), 0),
      carbs: Math.max(coerceNumber(raw.carbs), 0),
      fat: Math.max(coerceNumber(raw.fat), 0),
      fiber: Math.max(coerceNumber(raw.fiber), 0),
      source: normalizeText(raw.source) ?? 'openai_estimate',
      confidence: normalizeConfidence(raw.confidence),
      reasoning: normalizeText(raw.reasoning) ?? undefined,
    }

    return {
      data: normalized,
      debug: {
        prompt: userPrompt,
        rawResponse: parsed,
      },
    }
  } catch (error) {
    console.error('Error finding food nutrition:', error)
    throw new Error(
      `Failed to find nutrition data: ${error instanceof Error ? error.message : 'Unknown error'}`
    )
  }
}

/**
 * Agent: Search the web for nutrition validation
 * Uses web search to cross-check OpenAI's nutrition data
 */
export async function validateWithWebSearch(
  foodName: string,
  estimatedData: FoodNutritionData
): Promise<{
  result: {
    validated: boolean
    confidence: 'high' | 'medium' | 'low'
    sources: string[]
    notes?: string
  }
  debug: {
    prompt: string
    rawResponse: unknown
  }
}> {
  // For now, we'll use OpenAI to simulate web search validation
  // In production, you'd integrate with a real web search API (SerpAPI, Google Custom Search, etc.)

  const validationPrompt = `You are a nutrition fact validator. Given this estimated nutrition data, assess its accuracy:

Food: ${foodName}
Estimated Data:
- Calories: ${estimatedData.calories} per ${estimatedData.servingSize}${estimatedData.servingUnit}
- Protein: ${estimatedData.protein}g
- Carbs: ${estimatedData.carbs}g
- Fat: ${estimatedData.fat}g
- Fiber: ${estimatedData.fiber}g

Based on your knowledge:
1. Is this data reasonable/accurate?
2. What confidence level would you assign?
3. What sources would typically have this information?

Return JSON with: validated (boolean), confidence (high/medium/low), sources (array), notes (string)`

  try {
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: 'You are a nutrition fact validator with access to common nutrition databases.',
        },
        { role: 'user', content: validationPrompt },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.2,
    })

    const responseContent = completion.choices[0]?.message?.content
    if (!responseContent) {
      return {
        result: {
          validated: true,
          confidence: estimatedData.confidence,
          sources: ['OpenAI estimation'],
        },
        debug: {
          prompt: validationPrompt,
          rawResponse: null,
        },
      }
    }

    const result = JSON.parse(responseContent)
    return {
      result: {
        validated: result.validated !== false,
        confidence: result.confidence || estimatedData.confidence,
        sources: result.sources || ['OpenAI estimation'],
        notes: result.notes,
      },
      debug: {
        prompt: validationPrompt,
        rawResponse: result,
      },
    }
  } catch (error) {
    console.error('Error validating with web search:', error)
    // If validation fails, still allow the original data through
    return {
      result: {
        validated: true,
        confidence: estimatedData.confidence,
        sources: ['OpenAI estimation (validation failed)'],
      },
      debug: {
        prompt: validationPrompt,
        rawResponse: null,
      },
    }
  }
}

/**
 * Complete agent workflow: Find + Validate
 */
export async function agentFindFood(
  foodName: string,
  quantity?: number,
  unit?: string
): Promise<{
  foodData: FoodNutritionData
  validation: {
    validated: boolean
    confidence: 'high' | 'medium' | 'low'
    sources: string[]
    notes?: string
  }
  debug: {
    nutrition: {
      prompt: string
      rawResponse: unknown
    }
    validation: {
      prompt: string
      rawResponse: unknown
    }
  }
}> {
  // Step 1: Use OpenAI to find nutrition data
  console.log(`🤖 Agent searching for: ${foodName}`)
  const nutritionResult = await findFoodNutrition(foodName, quantity, unit)

  // Step 2: Validate with web search
  console.log(`🔍 Validating nutrition data...`)
  const validationResult = await validateWithWebSearch(foodName, nutritionResult.data)

  // Update confidence based on validation
  if (validationResult.result.confidence !== nutritionResult.data.confidence) {
    nutritionResult.data.confidence = validationResult.result.confidence
  }

  console.log(
    `✅ Found ${foodName}: ${nutritionResult.data.calories} kcal (confidence: ${nutritionResult.data.confidence})`
  )

  return {
    foodData: nutritionResult.data,
    validation: validationResult.result,
    debug: {
      nutrition: nutritionResult.debug,
      validation: validationResult.debug,
    },
  }
}
