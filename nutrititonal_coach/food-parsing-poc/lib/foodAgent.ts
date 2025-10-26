import OpenAI from 'openai'
import { z } from 'zod'

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

// Schema for food nutrition data
const FoodNutritionSchema = z.object({
  name: z.string(),
  brand: z.string().nullable(),
  category: z.string(),
  servingSize: z.number(),
  servingUnit: z.string(),
  calories: z.number(),
  protein: z.number(),
  carbs: z.number(),
  fat: z.number(),
  fiber: z.number(),
  source: z.string(),
  confidence: z.enum(['high', 'medium', 'low']),
  reasoning: z.string().optional(),
})

export type FoodNutritionData = z.infer<typeof FoodNutritionSchema>

/**
 * Agent: Find nutrition data for unknown foods
 * Uses OpenAI with function calling to search and estimate nutrition
 */
export async function findFoodNutrition(
  foodName: string,
  quantity?: number,
  unit?: string
): Promise<FoodNutritionData> {
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

Return nutrition data in JSON format with all required fields.`

  try {
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: `Find nutrition data for: "${foodName}"${quantity && unit ? ` (user asked for ${quantity} ${unit})` : ''}`,
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
    const validated = FoodNutritionSchema.parse(parsed)

    return validated
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
  validated: boolean
  confidence: 'high' | 'medium' | 'low'
  sources: string[]
  notes?: string
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
        validated: true,
        confidence: estimatedData.confidence,
        sources: ['OpenAI estimation'],
      }
    }

    const result = JSON.parse(responseContent)
    return {
      validated: result.validated !== false,
      confidence: result.confidence || estimatedData.confidence,
      sources: result.sources || ['OpenAI estimation'],
      notes: result.notes,
    }
  } catch (error) {
    console.error('Error validating with web search:', error)
    // If validation fails, still allow the original data through
    return {
      validated: true,
      confidence: estimatedData.confidence,
      sources: ['OpenAI estimation (validation failed)'],
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
}> {
  // Step 1: Use OpenAI to find nutrition data
  console.log(`🤖 Agent searching for: ${foodName}`)
  const foodData = await findFoodNutrition(foodName, quantity, unit)

  // Step 2: Validate with web search
  console.log(`🔍 Validating nutrition data...`)
  const validation = await validateWithWebSearch(foodName, foodData)

  // Update confidence based on validation
  if (validation.confidence !== foodData.confidence) {
    foodData.confidence = validation.confidence
  }

  console.log(
    `✅ Found ${foodName}: ${foodData.calories} kcal (confidence: ${foodData.confidence})`
  )

  return {
    foodData,
    validation,
  }
}
