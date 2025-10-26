import { NextRequest, NextResponse } from 'next/server'
import { saveMeal } from '@/lib/nutrition'
import { prisma } from '@/lib/prisma'

// GET /api/meals - Retrieve meal history
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')

    if (!userId) {
      return NextResponse.json(
        { error: 'Missing userId in query params' },
        { status: 400 }
      )
    }

    const meals = await prisma.meal.findMany({
      include: {
        foods: true,
      },
      orderBy: {
        timestamp: 'desc',
      },
      where: {
        userId,
      },
      take: 20, // Get last 20 meals
    })

    return NextResponse.json({
      success: true,
      data: meals,
    })
  } catch (error) {
    console.error('Error fetching meals:', error)

    return NextResponse.json(
      {
        error: 'Failed to fetch meals',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}

// POST /api/meals - Save a new meal
export async function POST(request: Request) {
  try {
    const { rawInput, nutrition, mealType, userId } = await request.json()

    if (!rawInput || !nutrition || !userId) {
      return NextResponse.json(
        { error: 'Missing required fields: rawInput, nutrition, userId' },
        { status: 400 }
      )
    }

    // Save the meal to database
    const result = await saveMeal({
      rawInput,
      mealData: nutrition,
      mealType,
      userId,
    })

    // Fetch the saved meal with all details
    const savedMeal = await prisma.meal.findUnique({
      where: { id: result.id },
      include: {
        foods: true,
      },
    })

    return NextResponse.json({
      success: true,
      data: savedMeal,
      message: 'Meal saved successfully',
    })
  } catch (error) {
    console.error('Error saving meal:', error)

    return NextResponse.json(
      {
        error: 'Failed to save meal',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
