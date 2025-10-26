import { NextResponse } from 'next/server'
import { parseFoodInput } from '@/lib/openai'
import { calculateMealNutrition } from '@/lib/nutrition'

export async function POST(request: Request) {
  try {
    const { input } = await request.json()

    if (!input || typeof input !== 'string') {
      return NextResponse.json(
        { error: 'Invalid input. Please provide a food description.' },
        { status: 400 }
      )
    }

    const parsedFoods = await parseFoodInput(input)

    if (!parsedFoods || parsedFoods.length === 0) {
      return NextResponse.json(
        { error: 'Could not parse any food items from the input.' },
        { status: 400 }
      )
    }

    const nutrition = await calculateMealNutrition(parsedFoods)

    return NextResponse.json({
      success: true,
      data: {
        rawInput: input,
        parsedFoods,
        nutrition,
      },
    })
  } catch (error) {
    console.error('Error in parse-food API:', error)

    return NextResponse.json(
      {
        error: 'Failed to parse food input',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
