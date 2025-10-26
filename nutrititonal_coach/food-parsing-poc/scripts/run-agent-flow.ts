import 'dotenv/config'
import { NextRequest } from 'next/server'
import { POST as profilePost } from '@/app/api/profile/route'
import { POST as parsePost } from '@/app/api/parse-food/route'
import { POST as findFoodPost, PUT as findFoodPut } from '@/app/api/find-food/route'
import { POST as mealsPost } from '@/app/api/meals/route'
import { GET as summaryGet } from '@/app/api/daily-summary/route'
import type { Food } from '@prisma/client'
import type { FoodNutritionData } from '@/lib/foodAgent'
import type { MealNutrition, NutritionData } from '@/lib/nutrition'
import type { ParsedFoodItem } from '@/lib/openai'
import { prisma } from '@/lib/prisma'

interface ApiSuccess<T> {
  success: true
  data: T
}

interface ApiErrorPayload {
  success?: false
  error?: string
  details?: unknown
  [key: string]: unknown
}

interface ProfileResponseData {
  userId: string
  profile: Record<string, unknown>
}

interface ParseFoodResponse {
  rawInput: string
  parsedFoods: ParsedFoodItem[]
  nutrition: MealNutrition
}

interface AgentValidation {
  validated: boolean
  confidence: 'high' | 'medium' | 'low'
  sources: string[]
  notes?: string
}

interface AgentResponse {
  foodData: FoodNutritionData
  validation: AgentValidation
}

interface DailySummaryTotals {
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
}

interface DailySummaryData {
  date: string
  totals: DailySummaryTotals
  remaining: DailySummaryTotals
}

function isApiSuccess<T>(payload: unknown): payload is ApiSuccess<T> {
  if (typeof payload !== 'object' || payload === null) {
    return false
  }

  const record = payload as Record<string, unknown>
  return record.success === true && 'data' in record
}

async function callPostJson<T>(
  handler: (request: Request) => Promise<Response>,
  url: string,
  body: unknown
): Promise<T> {
  const request = new Request(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })

  const response = await handler(request)
  const json = (await response.json()) as ApiSuccess<T> | ApiErrorPayload

  if (!isApiSuccess<T>(json)) {
    console.error(`POST ${url} failed`, json)
    throw new Error(`Request to ${url} failed`)
  }

  return json.data
}

async function callPutJson<T>(
  handler: (request: Request) => Promise<Response>,
  url: string,
  body: unknown
): Promise<T> {
  const request = new Request(url, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })

  const response = await handler(request)
  const json = (await response.json()) as ApiSuccess<T> | ApiErrorPayload

  if (!isApiSuccess<T>(json)) {
    console.error(`PUT ${url} failed`, json)
    throw new Error(`Request to ${url} failed`)
  }

  return json.data
}

async function callSummary(userId: string) {
  const url = `http://localhost/api/daily-summary?userId=${encodeURIComponent(
    userId
  )}&date=${encodeURIComponent(new Date().toISOString())}`
  const request = new NextRequest(url)
  const response = await summaryGet(request)
  const json = (await response.json()) as ApiSuccess<DailySummaryData> | ApiErrorPayload
  if (!isApiSuccess<DailySummaryData>(json)) {
    console.error('GET /daily-summary failed', json)
    throw new Error('Summary request failed')
  }
  return json.data
}

async function main() {
  console.log('▶️  Creating demo profile...')
  const profile = await callPostJson<ProfileResponseData>(
    profilePost,
    'http://localhost/api/profile',
    {
      profile: {
        name: 'Alex Automation',
        heightCm: 170,
        weightKg: 68,
        age: 32,
        gender: 'female',
        activityLevel: 'moderate',
        goal: 'moderate_loss',
        dietPreference: 'veg_eggs',
        mealPattern: '3_meals',
      },
    }
  )

  const userId = profile.userId
  console.log(`✅ Profile ready for user ${userId}`)

  console.log('▶️  Parsing meal with missing foods...')
  const mealCandidates = [
    'dragonfruit smoothie',
    'matcha coconut smoothie',
    'tropical pitaya smoothie',
    'ube protein latte',
  ]

  await prisma.food.deleteMany({
    where: {
      name: {
        in: mealCandidates.map((candidate) => candidate.toLowerCase()),
      },
    },
  })

  let firstParse: ParseFoodResponse | undefined
  let targetFood: NutritionData | undefined

  for (const candidate of mealCandidates) {
    const mealInput = `Lunch: 1 cup greek yogurt, 1 tbsp chia, 1 ${candidate}`
    const attempt = await callPostJson<ParseFoodResponse>(
      parsePost,
      'http://localhost/api/parse-food',
      {
        input: mealInput,
      }
    )

    const unmatchedFoods = attempt.nutrition.foods.filter((food: NutritionData) => !food.matched)
    if (unmatchedFoods.length > 0) {
      firstParse = attempt
      targetFood = unmatchedFoods[0]
      break
    }
  }

  if (!firstParse || !targetFood) {
    throw new Error(
      'Expected to find an unknown food for agent flow test. Consider resetting the database seed or adjusting the candidate list.'
    )
  }

  console.log(
    `Parsed ${firstParse.nutrition.foods.length} foods. Matched: ${
      firstParse.nutrition.foods.filter((f: NutritionData) => f.matched).length
    }`
  )
  console.log(`🤖 Invoking agent for "${targetFood.foodName}"...`)
  const agentResult = await callPostJson<AgentResponse>(findFoodPost, 'http://localhost/api/find-food', {
    foodName: targetFood.foodName,
    quantity: targetFood.quantity,
    unit: targetFood.unit,
  })

  console.log(
    `Agent found: ${agentResult.foodData.name} (${agentResult.validation.confidence} confidence)`
  )

  console.log('📦 Adding agent-discovered food to database...')
  await callPutJson<Food>(findFoodPut, 'http://localhost/api/find-food', {
    foodData: agentResult.foodData,
  })

  console.log('🔁 Re-parsing meal to confirm resolution...')
  const secondParse = await callPostJson<ParseFoodResponse>(parsePost, 'http://localhost/api/parse-food', {
    input: firstParse.rawInput,
  })

  const stillUnknown = secondParse.nutrition.foods.filter((food: NutritionData) => !food.matched)
  console.log(
    `After agent add, unmatched foods: ${stillUnknown.length}. Calories: ${secondParse.nutrition.totals.calories}`
  )

  if (stillUnknown.length > 0) {
    throw new Error('Agent flow did not resolve all unknown foods')
  }

  console.log('💾 Saving meal to history...')
  await callPostJson<{ id: string }>(mealsPost, 'http://localhost/api/meals', {
    rawInput: secondParse.rawInput,
    nutrition: secondParse.nutrition,
    userId,
  })

  console.log('📊 Fetching daily summary...')
  const summary = await callSummary(userId)
  console.log(
    `Summary totals: ${summary.totals.calories} kcal, remaining protein ${summary.remaining.protein}g`
  )

  console.log('✅ Agent-assisted flow completed successfully.')
}

main().catch((error) => {
  console.error('❌ Flow failed', error)
  process.exit(1)
})
