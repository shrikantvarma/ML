import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import {
  OnboardingInput,
  calculateDailyTargets,
} from '@/lib/profile'

function normalizeOnboardingPayload(payload: any): OnboardingInput {
  if (!payload) {
    throw new Error('Profile payload is required')
  }

  return {
    name: payload.name?.trim() || undefined,
    heightCm: Number(payload.heightCm),
    weightKg: Number(payload.weightKg),
    age: Number(payload.age),
    gender: payload.gender,
    activityLevel: payload.activityLevel,
    goal: payload.goal,
    dietPreference: payload.dietPreference,
    mealPattern: payload.mealPattern,
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')

    if (!userId) {
      return NextResponse.json({
        success: true,
        data: null,
      })
    }

    const profile = await prisma.profile.findUnique({
      where: { userId },
      include: {
        user: true,
      },
    })

    if (!profile) {
      return NextResponse.json({
        success: true,
        data: null,
      })
    }

    return NextResponse.json({
      success: true,
      data: {
        userId,
        profile,
      },
    })
  } catch (error) {
    console.error('Error fetching profile:', error)
    return NextResponse.json(
      { error: 'Failed to load profile' },
      { status: 500 }
    )
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const userId: string | null = body.userId ?? null

    const onboardingInput = normalizeOnboardingPayload(body.profile)
    const macros = calculateDailyTargets(onboardingInput)

    const user = userId
      ? await prisma.user.update({
          where: { id: userId },
          data: {
            name: onboardingInput.name ?? undefined,
          },
        })
      : await prisma.user.create({
          data: {
            name: onboardingInput.name ?? 'You',
          },
        })

    const savedProfile = await prisma.profile.upsert({
      where: { userId: user.id },
      update: {
        heightCm: onboardingInput.heightCm,
        weightKg: onboardingInput.weightKg,
        age: onboardingInput.age,
        gender: onboardingInput.gender,
        activityLevel: onboardingInput.activityLevel,
        goal: onboardingInput.goal,
        dietPreference: onboardingInput.dietPreference,
        mealPattern: onboardingInput.mealPattern,
        dailyCalories: macros.calories,
        dailyProtein: macros.protein,
        dailyCarbs: macros.carbs,
        dailyFat: macros.fat,
        dailyFiber: macros.fiber,
      },
      create: {
        userId: user.id,
        heightCm: onboardingInput.heightCm,
        weightKg: onboardingInput.weightKg,
        age: onboardingInput.age,
        gender: onboardingInput.gender,
        activityLevel: onboardingInput.activityLevel,
        goal: onboardingInput.goal,
        dietPreference: onboardingInput.dietPreference,
        mealPattern: onboardingInput.mealPattern,
        dailyCalories: macros.calories,
        dailyProtein: macros.protein,
        dailyCarbs: macros.carbs,
        dailyFat: macros.fat,
        dailyFiber: macros.fiber,
      },
    })

    return NextResponse.json({
      success: true,
      data: {
        userId: user.id,
        profile: savedProfile,
      },
    })
  } catch (error) {
    console.error('Error saving profile:', error)
    return NextResponse.json(
      {
        error: 'Failed to save profile',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
