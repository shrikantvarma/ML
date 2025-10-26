export interface OnboardingInput {
  name?: string
  heightCm: number
  weightKg: number
  age: number
  gender: 'male' | 'female' | 'non_binary' | 'prefer_not_to_say' | string
  activityLevel: 'sedentary' | 'light' | 'moderate' | 'active' | 'athlete' | string
  goal: 'maintain' | 'moderate_loss' | 'aggressive_loss' | 'moderate_gain' | 'aggressive_gain' | string
  dietPreference: 'veg' | 'veg_eggs' | 'non_veg' | string
  mealPattern?: string
}

interface MacroBreakdown {
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
}

const activityMultipliers: Record<string, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  athlete: 1.9,
}

const goalAdjustments: Record<string, number> = {
  maintain: 0,
  moderate_loss: -300,
  aggressive_loss: -500,
  moderate_gain: 250,
  aggressive_gain: 450,
}

const proteinPerKgMap: Record<string, number> = {
  maintain: 1.8,
  moderate_loss: 2,
  aggressive_loss: 2.2,
  moderate_gain: 2,
  aggressive_gain: 2.2,
}

function getActivityMultiplier(level: string) {
  return activityMultipliers[level] ?? activityMultipliers.moderate
}

function getGoalAdjustment(goal: string) {
  return goalAdjustments[goal] ?? goalAdjustments.maintain
}

function getProteinPerKg(goal: string) {
  return proteinPerKgMap[goal] ?? proteinPerKgMap.maintain
}

function calculateBMR({
  weightKg,
  heightCm,
  age,
  gender,
}: Pick<OnboardingInput, 'weightKg' | 'heightCm' | 'age' | 'gender'>) {
  // Mifflin-St Jeor Equation
  const base = 10 * weightKg + 6.25 * heightCm - 5 * age
  const genderOffset =
    gender === 'female'
      ? -161
      : gender === 'male'
      ? 5
      : -78 // Neutral midpoint

  return base + genderOffset
}

export function calculateDailyTargets(input: OnboardingInput): MacroBreakdown {
  const bmr = calculateBMR(input)
  const activityMultiplier = getActivityMultiplier(input.activityLevel)
  const goalAdjustment = getGoalAdjustment(input.goal)

  const maintenanceCalories = bmr * activityMultiplier
  const calories = Math.max(1200, Math.round(maintenanceCalories + goalAdjustment))

  // Protein scaled by goal and vegetarian preference (slightly higher for veg)
  const proteinPerKg = getProteinPerKg(input.goal)
  const protein =
    Math.round(
      (input.dietPreference === 'veg' ? proteinPerKg + 0.2 : proteinPerKg) *
        input.weightKg
    ) || 120

  const proteinCalories = protein * 4

  // Fat as ~25% of total calories
  const fatCalories = calories * 0.25
  const fat = Math.round(fatCalories / 9)

  // Carbs fill the remainder
  const remainingCalories = Math.max(calories - proteinCalories - fatCalories, 0)
  const carbs = Math.round(remainingCalories / 4)

  // Fiber target heuristic
  const fiberBase = input.dietPreference === 'non_veg' ? 28 : 32
  const fiber = Math.round(fiberBase + (input.mealPattern ? 2 : 0))

  return {
    calories,
    protein,
    carbs,
    fat,
    fiber,
  }
}

export interface DailySummaryInput {
  totals: {
    calories: number
    protein: number
    carbs: number
    fat: number
    fiber: number
  }
  targets: MacroBreakdown
}

export function calculateRemaining({
  totals,
  targets,
}: DailySummaryInput): MacroBreakdown {
  return {
    calories: Math.round(targets.calories - totals.calories),
    protein: Math.round(targets.protein - totals.protein),
    carbs: Math.round(targets.carbs - totals.carbs),
    fat: Math.round(targets.fat - totals.fat),
    fiber: Math.round(targets.fiber - totals.fiber),
  }
}
