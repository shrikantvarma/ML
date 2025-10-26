import { NextResponse } from 'next/server'
import { agentFindFood } from '@/lib/foodAgent'
import { prisma } from '@/lib/prisma'

// POST /api/find-food - Agent finds nutrition data for unknown foods
export async function POST(request: Request) {
  try {
    const { foodName, quantity, unit } = await request.json()

    if (!foodName) {
      return NextResponse.json({ error: 'foodName is required' }, { status: 400 })
    }

    // Use the agent to find and validate nutrition data
    const result = await agentFindFood(foodName, quantity, unit)

    return NextResponse.json({
      success: true,
      data: {
        foodData: result.foodData,
        validation: result.validation,
        message: `Found nutrition data for "${foodName}" with ${result.validation.confidence} confidence`,
      },
    })
  } catch (error) {
    console.error('Error in find-food API:', error)

    return NextResponse.json(
      {
        error: 'Failed to find food nutrition data',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}

// POST /api/find-food/confirm - User confirms and adds food to database
export async function PUT(request: Request) {
  try {
    const { foodData } = await request.json()

    if (!foodData) {
      return NextResponse.json({ error: 'foodData is required' }, { status: 400 })
    }

    // Add the food to the database
    const newFood = await prisma.food.create({
      data: {
        name: foodData.name.toLowerCase(),
        brand: foodData.brand,
        category: foodData.category,
        servingSize: foodData.servingSize,
        servingUnit: foodData.servingUnit,
        calories: foodData.calories,
        protein: foodData.protein,
        carbs: foodData.carbs,
        fat: foodData.fat,
        fiber: foodData.fiber,
        source: 'agent', // Mark as agent-discovered
      },
    })

    return NextResponse.json({
      success: true,
      data: newFood,
      message: `Added "${foodData.name}" to database`,
    })
  } catch (error) {
    console.error('Error adding food to database:', error)

    return NextResponse.json(
      {
        error: 'Failed to add food to database',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
