import 'dotenv/config'
import { NextRequest } from 'next/server'
import { POST as profilePost } from '@/app/api/profile/route'
import { POST as parsePost } from '@/app/api/parse-food/route'
import { POST as findFoodPost, PUT as findFoodPut } from '@/app/api/find-food/route'
import { POST as mealsPost } from '@/app/api/meals/route'
import { GET as summaryGet } from '@/app/api/daily-summary/route'

type ProfileResponse = {
  success: boolean
  data: {
    userId: string
    profile: any
  }
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
  const json = (await response.json()) as T

  if (!('success' in json) || !(json as any).success) {
    console.error(`POST ${url} failed`, json)
    throw new Error(`Request to ${url} failed`)
  }

  return json
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
  const json = (await response.json()) as T

  if (!('success' in json) || !(json as any).success) {
    console.error(`PUT ${url} failed`, json)
    throw new Error(`Request to ${url} failed`)
  }

  return json
}

async function callSummary(userId: string) {
  const url = `http://localhost/api/daily-summary?userId=${encodeURIComponent(
    userId
  )}&date=${encodeURIComponent(new Date().toISOString())}`
  const request = new NextRequest(url)
  const response = await summaryGet(request)
  const json = await response.json()
  if (!json.success) {
    console.error('GET /daily-summary failed', json)
    throw new Error('Summary request failed')
  }
  return json
}

async function main() {
  console.log('▶️  Creating demo profile...')
  const profile = await callPostJson<ProfileResponse>(
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

  const userId = profile.data.userId
  console.log(`✅ Profile ready for user ${userId}`)

  console.log('▶️  Parsing meal with missing foods...')
  const firstParse = await callPostJson<any>(parsePost, 'http://localhost/api/parse-food', {
    input: 'Lunch: 1 cup greek yogurt, 1 tbsp chia, 1 dragonfruit smoothie',
  })

  console.log(
    `Parsed ${firstParse.data.nutrition.foods.length} foods. Matched: ${
      firstParse.data.nutrition.foods.filter((f: any) => f.matched).length
    }`
  )

  const unknownFoods = firstParse.data.nutrition.foods.filter((food: any) => !food.matched)
  if (unknownFoods.length === 0) {
    throw new Error('Expected at least one unknown food for agent flow test')
  }

  const targetFood = unknownFoods[0]
  console.log(`🤖 Invoking agent for "${targetFood.foodName}"...`)
  const agentResult = await callPostJson<any>(findFoodPost, 'http://localhost/api/find-food', {
    foodName: targetFood.foodName,
    quantity: targetFood.quantity,
    unit: targetFood.unit,
  })

  console.log(
    `Agent found: ${agentResult.data.foodData.name} (${agentResult.data.validation.confidence} confidence)`
  )

  console.log('📦 Adding agent-discovered food to database...')
  await callPutJson<any>(findFoodPut, 'http://localhost/api/find-food', {
    foodData: agentResult.data.foodData,
  })

  console.log('🔁 Re-parsing meal to confirm resolution...')
  const secondParse = await callPostJson<any>(parsePost, 'http://localhost/api/parse-food', {
    input: firstParse.data.rawInput,
  })

  const stillUnknown = secondParse.data.nutrition.foods.filter((food: any) => !food.matched)
  console.log(
    `After agent add, unmatched foods: ${stillUnknown.length}. Calories: ${secondParse.data.nutrition.totals.calories}`
  )

  if (stillUnknown.length > 0) {
    throw new Error('Agent flow did not resolve all unknown foods')
  }

  console.log('💾 Saving meal to history...')
  await callPostJson<any>(mealsPost, 'http://localhost/api/meals', {
    rawInput: secondParse.data.rawInput,
    nutrition: secondParse.data.nutrition,
    userId,
  })

  console.log('📊 Fetching daily summary...')
  const summary = await callSummary(userId)
  console.log(
    `Summary totals: ${summary.data.totals.calories} kcal, remaining protein ${summary.data.remaining.protein}g`
  )

  console.log('✅ Agent-assisted flow completed successfully.')
}

main().catch((error) => {
  console.error('❌ Flow failed', error)
  process.exit(1)
})
