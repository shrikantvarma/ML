import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { calculateRemaining } from '@/lib/profile'

function startOfDay(date: Date) {
  const copy = new Date(date)
  copy.setHours(0, 0, 0, 0)
  return copy
}

function endOfDay(date: Date) {
  const copy = new Date(date)
  copy.setHours(23, 59, 59, 999)
  return copy
}

function buildSuggestions({
  remaining,
  totals,
  targets,
}: {
  remaining: Record<string, number>
  totals: Record<string, number>
  targets: Record<string, number>
}) {
  const tips: string[] = []

  if (remaining.protein > 15) {
    tips.push(
      `You still need ~${remaining.protein}g protein. Add Greek yogurt, paneer, or a Barebells bar to close the gap.`
    )
  }

  if (remaining.fiber > 5) {
    tips.push(
      `Fiber is low by ~${remaining.fiber}g. Consider leafy greens, chia seeds, or berries in your next meal.`
    )
  }

  if (remaining.calories < -100) {
    tips.push(
      `You're ${Math.abs(remaining.calories)} kcal over target. Keep dinner lighter and emphasize lean protein + veggies.`
    )
  }

  if (remaining.fat < -10) {
    tips.push(
      `Fat intake is high today. Skip added oils and nuts for the next meal.`
    )
  }

  if (totals.carbs < targets.carbs * 0.6 && remaining.carbs > 25) {
    tips.push(
      `Carbs are still low. Add a slow-carb option like quinoa, roti, or fruit for stable energy.`
    )
  }

  if (tips.length === 0) {
    tips.push('Great balance so far! Keep your next meal light and protein-forward.')
  }

  return tips.slice(0, 3)
}

function buildClosingPlan({
  remaining,
  dietPreference,
}: {
  remaining: Record<string, number>
  dietPreference: string
}) {
  const options: { title: string; details: string }[] = []
  const proteinNeed = Math.max(remaining.protein, 0)
  const fiberNeed = Math.max(remaining.fiber, 0)
  const calNeed = Math.max(remaining.calories, 0)

  const prefersVeg = dietPreference === 'veg' || dietPreference === 'veg_eggs'

  if (proteinNeed > 5) {
    if (prefersVeg) {
      options.push({
        title: 'Greek yogurt + chia',
        details: '1 cup yogurt + 1 tbsp chia ≈ 25g protein, 8g fiber, 260 kcal',
      })
      options.push({
        title: 'Paneer scramble',
        details: '120g paneer sautéed with spinach ≈ 24g protein, 6g fat',
      })
    } else {
      options.push({
        title: 'Grilled chicken + veggies',
        details: '120g chicken + steamed broccoli ≈ 30g protein, 220 kcal',
      })
    }
  }

  if (fiberNeed > 5) {
    options.push({
      title: 'Leafy salad boost',
      details: 'Spinach + carrot + seeds adds ~7g fiber with minimal calories',
    })
  }

  if (calNeed < 150 && options.length === 0) {
    options.push({
      title: 'Light closeout',
      details: '½ Barebells bar + herbal tea ≈ 110 kcal, 10g protein',
    })
  }

  if (options.length === 0) {
    options.push({
      title: 'Day balanced',
      details: 'Totals look great. Hydrate and wind down! 🌙',
    })
  }

  return {
    headline:
      proteinNeed > 10 || fiberNeed > 5
        ? 'Balance the day with one of these combos:'
        : 'You are almost on target. Pick a light option if hungry:',
    options,
  }
}

function computeProgress(
  totals: Record<string, number>,
  targets: Record<string, number>
) {
  const progress: Record<string, number> = {}

  Object.entries(targets).forEach(([key, value]) => {
    if (value <= 0) {
      progress[key] = 0
    } else {
      progress[key] = Number(Math.min(totals[key] / value, 2).toFixed(2))
    }
  })

  return progress
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')
    const dateParam = searchParams.get('date')

    if (!userId) {
      return NextResponse.json(
        { error: 'Missing userId in query params' },
        { status: 400 }
      )
    }

    const profile = await prisma.profile.findUnique({
      where: { userId },
      include: { user: true },
    })

    if (!profile) {
      return NextResponse.json(
        { error: 'Profile not found for user' },
        { status: 404 }
      )
    }

    const targetDate = dateParam ? new Date(dateParam) : new Date()
    if (Number.isNaN(targetDate.valueOf())) {
      return NextResponse.json(
        { error: 'Invalid date parameter' },
        { status: 400 }
      )
    }

    const meals = await prisma.meal.findMany({
      where: {
        userId,
        timestamp: {
          gte: startOfDay(targetDate),
          lte: endOfDay(targetDate),
        },
      },
      include: {
        foods: true,
      },
      orderBy: {
        timestamp: 'asc',
      },
    })

    const totals = meals.reduce(
      (acc, meal) => {
        acc.calories += meal.totalCalories
        acc.protein += meal.totalProtein
        acc.carbs += meal.totalCarbs
        acc.fat += meal.totalFat
        acc.fiber += meal.totalFiber
        return acc
      },
      {
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        fiber: 0,
      }
    )

    const remaining = calculateRemaining({
      totals,
      targets: {
        calories: profile.dailyCalories,
        protein: profile.dailyProtein,
        carbs: profile.dailyCarbs,
        fat: profile.dailyFat,
        fiber: profile.dailyFiber,
      },
    })

    const suggestions = buildSuggestions({
      remaining,
      totals,
      targets: {
        calories: profile.dailyCalories,
        protein: profile.dailyProtein,
        carbs: profile.dailyCarbs,
        fat: profile.dailyFat,
        fiber: profile.dailyFiber,
      },
    })

    const progress = computeProgress(totals, {
      calories: profile.dailyCalories,
      protein: profile.dailyProtein,
      carbs: profile.dailyCarbs,
      fat: profile.dailyFat,
      fiber: profile.dailyFiber,
    })

    const closingPlan = buildClosingPlan({
      remaining,
      dietPreference: profile.dietPreference,
    })

    return NextResponse.json({
      success: true,
      data: {
        date: targetDate.toISOString(),
        profile,
        totals,
        remaining,
        progress,
        suggestions,
        closingPlan,
        meals,
      },
    })
  } catch (error) {
    console.error('Error building daily summary:', error)
    return NextResponse.json(
      { error: 'Failed to load daily summary' },
      { status: 500 }
    )
  }
}
