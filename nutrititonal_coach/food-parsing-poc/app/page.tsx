'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  BarChart3,
  Calendar,
  Check,
  MessageSquare,
  Plus,
  Send,
  Settings,
  X,
} from 'lucide-react'
import type { FoodNutritionData } from '@/lib/foodAgent'

type Screen = 'loading' | 'onboarding' | 'home' | 'chat' | 'endOfDay'

interface Profile {
  id: string
  userId: string
  name?: string | null
  heightCm: number
  weightKg: number
  age: number
  gender: string
  activityLevel: string
  goal: string
  dietPreference: string
  mealPattern?: string | null
  dailyCalories: number
  dailyProtein: number
  dailyCarbs: number
  dailyFat: number
  dailyFiber: number
}

interface DailySummary {
  date: string
  totals: Record<'calories' | 'protein' | 'carbs' | 'fat' | 'fiber', number>
  remaining: Record<'calories' | 'protein' | 'carbs' | 'fat' | 'fiber', number>
  progress: Record<'calories' | 'protein' | 'carbs' | 'fat' | 'fiber', number>
  suggestions: string[]
  closingPlan: {
    headline: string
    options: { title: string; details: string }[]
  }
  meals: {
    id: string
    rawInput: string
    timestamp: string
    totalCalories: number
    totalProtein: number
    totalCarbs: number
    totalFat: number
    totalFiber: number
  }[]
}

interface ChatMessage {
  id: string
  role: 'assistant' | 'user'
  text: string
}

interface ParsedFood {
  foodName: string
  quantity: number
  unit: string
}

interface NutritionFood {
  foodId: string | null
  foodName: string
  quantity: number
  unit: string
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
  matched: boolean
  confidence?: number
  suggestedName?: string
}

interface AgentValidation {
  validated: boolean
  confidence: 'high' | 'medium' | 'low'
  sources: string[]
  notes?: string
}

interface AgentMatchState {
  loading: boolean
  foodData: FoodNutritionData | null
  validation: AgentValidation | null
}

interface ParseResult {
  rawInput: string
  parsedFoods: ParsedFood[]
  nutrition: {
    foods: NutritionFood[]
    totals: Record<'calories' | 'protein' | 'carbs' | 'fat' | 'fiber', number>
  }
}

const defaultMessages: ChatMessage[] = [
  {
    id: 'welcome',
    role: 'assistant',
    text: 'Hey! Tell me what you just ate and I will log it for you. 🍽️',
  },
]

const createId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : Math.random().toString(36).slice(2)

function getProgressColor(percentage: number) {
  if (percentage >= 1.1) return 'bg-red-500'
  if (percentage >= 0.9) return 'bg-orange-500'
  return 'bg-green-500'
}

function formatRemaining(value: number, unit = 'g') {
  if (unit === 'kcal') {
    return value > 0 ? `+${value} kcal left` : `${Math.abs(value)} kcal over`
  }
  return value > 0
    ? `+${value}${unit} left`
    : `${Math.abs(value)}${unit} over`
}

function percentOfTarget(progress: number) {
  return Math.min(Math.max(progress * 100, 0), 200)
}

function NutrientBar({
  label,
  current,
  target,
  unit,
}: {
  label: string
  current: number
  target: number
  unit: 'g' | 'kcal'
}) {
  const percentage = target > 0 ? current / target : 0
  const colorClass = getProgressColor(percentage)
  const remaining = Math.round(target - current)

  const unmatchedFoods = currentResult?.nutrition.foods.filter((food) => !food.matched) ?? []
  const hasUnmatched = unmatchedFoods.length > 0

  return (
    <div className="mb-4">
      <div className="flex justify-between items-center mb-1">
        <span className="font-medium text-gray-700">{label}</span>
        <span className="text-sm text-gray-600">
          {Math.round(current)}
          {unit} / {Math.round(target)}
          {unit}
        </span>
      </div>
      <div className="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
        <div
          className={`h-full ${colorClass} transition-all duration-300`}
          style={{ width: `${percentOfTarget(percentage)}%` }}
        />
      </div>
      <div className="text-right mt-1">
        <span
          className={`text-xs ${
            remaining > 0 ? 'text-green-600' : 'text-red-600'
          }`}
        >
          {formatRemaining(remaining, unit)}
        </span>
      </div>
    </div>
  )
}

function OnboardingForm({
  onComplete,
  loading,
}: {
  onComplete: (result: { userId: string; profile: Profile }) => void
  loading: boolean
}) {
  const [formState, setFormState] = useState({
    name: 'Alex',
    heightCm: 170,
    weightKg: 68,
    age: 32,
    gender: 'female',
    activityLevel: 'moderate',
    goal: 'moderate_loss',
    dietPreference: 'veg_eggs',
    mealPattern: '3_meals',
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleChange = (
    field: keyof typeof formState,
    value: string | number
  ) => {
    setFormState((prev) => ({
      ...prev,
      [field]:
        field === 'heightCm' ||
        field === 'weightKg' ||
        field === 'age'
          ? Number(value)
          : value,
    }))
  }

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)

    try {
      const response = await fetch('/api/profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: formState }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to save profile')
      }

      onComplete(data.data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save profile')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="max-w-3xl mx-auto bg-white rounded-2xl shadow-xl p-8">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-800">
            Build Your Plan 🔍
          </h1>
          <p className="text-gray-600">
            Let&apos;s personalize your daily targets in under a minute.
          </p>
        </div>
        <Calendar className="text-green-500" size={28} />
      </div>

      <form onSubmit={handleSubmit} className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Name
          </label>
          <input
            type="text"
            value={formState.name}
            onChange={(e) => handleChange('name', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Age
          </label>
          <input
            type="number"
            value={formState.age}
            min={16}
            onChange={(e) => handleChange('age', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Height (cm)
          </label>
          <input
            type="number"
            value={formState.heightCm}
            min={120}
            onChange={(e) => handleChange('heightCm', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Weight (kg)
          </label>
          <input
            type="number"
            value={formState.weightKg}
            min={35}
            onChange={(e) => handleChange('weightKg', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Gender
          </label>
          <select
            value={formState.gender}
            onChange={(e) => handleChange('gender', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          >
            <option value="female">Female</option>
            <option value="male">Male</option>
            <option value="non_binary">Non-binary</option>
            <option value="prefer_not_to_say">Prefer not to say</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Activity Level
          </label>
          <select
            value={formState.activityLevel}
            onChange={(e) => handleChange('activityLevel', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          >
            <option value="sedentary">Sedentary</option>
            <option value="light">Light (1-2 workouts/week)</option>
            <option value="moderate">Moderate (3-4 workouts/week)</option>
            <option value="active">Active (daily training)</option>
            <option value="athlete">Athlete</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Goal
          </label>
          <select
            value={formState.goal}
            onChange={(e) => handleChange('goal', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          >
            <option value="maintain">Maintain</option>
            <option value="moderate_loss">Moderate loss (-300 kcal)</option>
            <option value="aggressive_loss">Aggressive loss (-500 kcal)</option>
            <option value="moderate_gain">Lean gain (+250 kcal)</option>
            <option value="aggressive_gain">Aggressive gain (+450 kcal)</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Diet Preference
          </label>
          <select
            value={formState.dietPreference}
            onChange={(e) => handleChange('dietPreference', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          >
            <option value="veg">Vegetarian</option>
            <option value="veg_eggs">Vegetarian + eggs</option>
            <option value="non_veg">Non-vegetarian</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Meal Pattern
          </label>
          <select
            value={formState.mealPattern}
            onChange={(e) => handleChange('mealPattern', e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 focus:border-green-500 focus:outline-none"
          >
            <option value="3_meals">3 meals / day</option>
            <option value="4_meals">4 meals / day</option>
            <option value="snack_focused">Snacks + 2 meals</option>
          </select>
        </div>

        <div className="md:col-span-2 flex justify-end gap-3 pt-2">
          {error && (
            <span className="text-sm text-red-600 self-center">{error}</span>
          )}
          <button
            type="submit"
            disabled={submitting || loading}
            className="bg-green-600 text-white px-6 py-3 rounded-xl font-medium hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition"
          >
            {submitting ? 'Calculating...' : 'Save & continue'}
          </button>
        </div>
      </form>
    </div>
  )
}

function Dashboard({
  profile,
  summary,
  onStartChat,
  onEndDay,
  onEditProfile,
}: {
  profile: Profile
  summary: DailySummary | null
  onStartChat: () => void
  onEndDay: () => void
  onEditProfile: () => void
}) {
  const remaining = summary?.remaining
    ? {
        calories: formatRemaining(summary.remaining.calories, 'kcal'),
        protein: formatRemaining(summary.remaining.protein),
        carbs: formatRemaining(summary.remaining.carbs),
        fat: formatRemaining(summary.remaining.fat),
        fiber: formatRemaining(summary.remaining.fiber),
      }
    : null

  return (
    <div className="flex flex-col h-full bg-gradient-to-b from-green-50 to-white">
      <div className="bg-white shadow-sm p-4">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-2xl font-bold text-gray-800">
              Hey {profile.name || 'friend'}! 👋
            </h1>
            <p className="text-sm text-gray-600">
              {new Date().toLocaleDateString(undefined, {
                weekday: 'long',
                month: 'long',
                day: 'numeric',
              })}
            </p>
          </div>
          <button
            onClick={onEditProfile}
            className="p-2 hover:bg-gray-100 rounded-full"
          >
            <Settings size={22} className="text-gray-600" />
          </button>
        </div>
      </div>

      <div className="p-4 space-y-4">
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-4">
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-lg font-bold text-gray-800">Today&apos;s Progress</h2>
            <span className="text-sm text-gray-500">
              {summary
                ? `${Math.round(
                    Math.min(
                      (summary.totals.calories / profile.dailyCalories) * 100,
                      200
                    )
                  )}% of calorie goal`
                : 'Log your first meal to begin'}
            </span>
          </div>

          <div className="bg-gradient-to-r from-green-100 to-green-50 rounded-xl p-4 mb-4">
            <div className="flex justify-between items-center">
              <div>
                <p className="text-sm text-gray-600">Calories</p>
                <p className="text-3xl font-bold text-gray-800">
                  {Math.round(summary?.totals.calories ?? 0)}
                </p>
                <p className="text-sm text-green-600">
                  of {Math.round(profile.dailyCalories)} kcal
                </p>
              </div>
              {remaining && (
                <div className="text-right">
                  <p className="text-2xl font-bold text-green-600">
                    {summary?.remaining.calories ?? 0}
                  </p>
                  <p className="text-xs text-gray-600">remaining</p>
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <NutrientBar
                label="Protein"
                current={summary?.totals.protein ?? 0}
                target={profile.dailyProtein}
                unit="g"
              />
              <NutrientBar
                label="Carbs"
                current={summary?.totals.carbs ?? 0}
                target={profile.dailyCarbs}
                unit="g"
              />
            </div>
            <div>
              <NutrientBar
                label="Fat"
                current={summary?.totals.fat ?? 0}
                target={profile.dailyFat}
                unit="g"
              />
              <NutrientBar
                label="Fiber"
                current={summary?.totals.fiber ?? 0}
                target={profile.dailyFiber}
                unit="g"
              />
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="bg-white rounded-2xl shadow-lg p-4">
            <h3 className="font-semibold text-gray-700 mb-3">Quick Actions</h3>
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={onStartChat}
                className="bg-green-500 text-white rounded-xl p-4 flex items-center justify-center space-x-2 hover:bg-green-600 transition"
              >
                <MessageSquare size={20} />
                <span className="font-medium">Log Meal</span>
              </button>
              <button
                onClick={onEndDay}
                className="bg-blue-500 text-white rounded-xl p-4 flex items-center justify-center space-x-2 hover:bg-blue-600 transition"
              >
                <Check size={20} />
                <span className="font-medium">End Day</span>
              </button>
            </div>
          </div>

          <div className="bg-white rounded-2xl shadow-lg p-4">
            <h3 className="font-semibold text-gray-700 mb-3">Smart Prompts</h3>
            <ul className="space-y-2">
              {summary?.suggestions && summary.suggestions.length > 0 ? (
                summary.suggestions.map((tip, index) => (
                  <li
                    key={index}
                    className="text-sm text-gray-700 bg-orange-50 border-l-4 border-orange-500 rounded-md p-3"
                  >
                    {tip}
                  </li>
                ))
              ) : (
                <li className="text-sm text-gray-600">
                  Log a meal to unlock precision guidance.
                </li>
              )}
            </ul>
          </div>
        </div>

        <div className="bg-white rounded-2xl shadow-lg p-4">
          <h3 className="font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <BarChart3 size={18} className="text-green-500" />
            Recent Meals
          </h3>
          <div className="space-y-3">
            {summary?.meals.length ? (
              summary.meals.slice(0, 4).map((meal) => (
                <div
                  key={meal.id}
                  className="border border-gray-200 rounded-lg p-3 flex justify-between items-center"
                >
                  <div>
                    <p className="text-sm font-medium text-gray-800">
                      {meal.rawInput}
                    </p>
                    <p className="text-xs text-gray-500">
                      {new Date(meal.timestamp).toLocaleTimeString([], {
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </p>
                  </div>
                  <div className="text-xs text-gray-600 text-right">
                    <p>{Math.round(meal.totalCalories)} kcal</p>
                    <p>
                      {Math.round(meal.totalProtein)}P /{' '}
                      {Math.round(meal.totalCarbs)}C /{' '}
                      {Math.round(meal.totalFat)}F
                    </p>
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-gray-600">
                Meals you log will appear here instantly.
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function ChatLogger({
  userId,
  profile,
  onClose,
  onMealLogged,
}: {
  userId: string
  profile: Profile
  onClose: () => void
  onMealLogged: () => void
}) {
  const [messages, setMessages] = useState<ChatMessage[]>(defaultMessages)
  const [inputText, setInputText] = useState('')
  const [currentResult, setCurrentResult] = useState<ParseResult | null>(null)
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [agentResults, setAgentResults] = useState<Map<string, AgentMatchState>>(new Map())
  const [agentSearching, setAgentSearching] = useState<string | null>(null)
  const [agentSaving, setAgentSaving] = useState<string | null>(null)

  const requestParse = async (rawInput: string): Promise<ParseResult> => {
    const response = await fetch('/api/parse-food', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input: rawInput }),
    })

    const data = await response.json()

    if (!response.ok) {
      throw new Error(data.error || 'Failed to parse food')
    }

    return data.data as ParseResult
  }

  const appendMessage = (message: ChatMessage) => {
    setMessages((prev) => [...prev, message])
  }

  const handleSend = async () => {
    if (!inputText.trim()) return

    const userMessage: ChatMessage = {
      id: createId(),
      role: 'user',
      text: inputText.trim(),
    }
    appendMessage(userMessage)
    setInputText('')
    setLoading(true)
    setError(null)
    setAgentResults(new Map())
    setAgentSearching(null)
    setAgentSaving(null)
    setCurrentResult(null)

    try {
      const data = await requestParse(userMessage.text)
      setCurrentResult(data)
      appendMessage({
        id: createId(),
        role: 'assistant',
        text:
          'Here is what I detected. Review the breakdown and hit save when it looks right.',
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Parser failed')
      appendMessage({
        id: createId(),
        role: 'assistant',
        text:
          'I had trouble reading that. Try adding portion sizes like "1 cup" or "2 pieces".',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleFindFood = async (food: NutritionFood) => {
    setAgentSearching(food.foodName)
    setAgentResults((prev) => {
      const next = new Map(prev)
      next.set(food.foodName, {
        loading: true,
        foodData: null,
        validation: null,
      })
      return next
    })

    try {
      const response = await fetch('/api/find-food', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          foodName: food.foodName,
          quantity: food.quantity,
          unit: food.unit,
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to find food')
      }

      setAgentResults((prev) => {
        const next = new Map(prev)
        next.set(food.foodName, {
          loading: false,
          foodData: data.data.foodData,
          validation: data.data.validation,
        })
        return next
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Agent failed to find food')
      setAgentResults((prev) => {
        const next = new Map(prev)
        next.delete(food.foodName)
        return next
      })
    } finally {
      setAgentSearching(null)
    }
  }

  const handleConfirmFood = async (foodName: string) => {
    const agentState = agentResults.get(foodName)
    if (!agentState || !agentState.foodData || !currentResult) {
      return
    }

    setAgentSaving(foodName)
    setError(null)

    try {
      const response = await fetch('/api/find-food', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ foodData: agentState.foodData }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to add food to database')
      }

      appendMessage({
        id: createId(),
        role: 'assistant',
        text: `Added "${agentState.foodData.name}" to your food database. Recalculating the meal...`,
      })

      setLoading(true)
      try {
        const updated = await requestParse(currentResult.rawInput)
        setCurrentResult(updated)
        setAgentResults((prev) => {
          const next = new Map(prev)
          next.delete(foodName)
          return next
        })
        appendMessage({
          id: createId(),
          role: 'assistant',
          text: 'Updated totals with the new food information.',
        })
      } finally {
        setLoading(false)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add food to database')
    } finally {
      setAgentSaving(null)
    }
  }

  const handleSaveMeal = async () => {
    if (!currentResult) return

    const unresolved = currentResult.nutrition.foods.filter((food) => !food.matched)
    if (unresolved.length > 0) {
      setError('Resolve unknown foods before saving.')
      return
    }

    setSaving(true)
    setError(null)

    try {
      const response = await fetch('/api/meals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          rawInput: currentResult.rawInput,
          nutrition: currentResult.nutrition,
          userId,
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to save meal')
      }

      appendMessage({
        id: createId(),
        role: 'assistant',
        text: `Logged! ${Math.round(
          currentResult.nutrition.totals.calories
        )} kcal • ${Math.round(
          currentResult.nutrition.totals.protein
        )}g protein added to your day.`,
      })

      setCurrentResult(null)
      setAgentResults(new Map())
      onMealLogged()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save meal')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col h-full bg-white">
      <div className="bg-green-500 text-white p-4 shadow-md">
        <div className="flex items-center space-x-3">
          <button
            onClick={() => {
              onClose()
            }}
            className="hover:bg-green-600 rounded-full p-1"
          >
            <X size={24} />
          </button>
          <div>
            <h2 className="font-bold text-lg">Food Logger</h2>
            <p className="text-xs text-green-100">
              Natural language • Macro intelligence
            </p>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-gradient-to-b from-white to-green-50">
        {messages.map((message) => (
          <div
            key={message.id}
            className={`max-w-md rounded-2xl px-4 py-3 ${
              message.role === 'assistant'
                ? 'bg-white shadow border border-green-100 text-gray-800'
                : 'bg-green-500 text-white ml-auto'
            }`}
          >
            {message.text.split('\n').map((line, idx) => (
              <p key={idx} className="text-sm leading-relaxed">
                {line}
              </p>
            ))}
          </div>
        ))}

        {currentResult && (
          <div className="bg-white border border-green-200 rounded-2xl p-4 shadow-sm space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-semibold text-gray-800">
                  {currentResult.rawInput}
                </h3>
                <p className="text-xs text-gray-500">
                  Parsed {currentResult.nutrition.foods.length} item
                  {currentResult.nutrition.foods.length === 1 ? '' : 's'}
                </p>
              </div>
              <span className="text-sm font-semibold text-green-600">
                {Math.round(currentResult.nutrition.totals.calories)} kcal
              </span>
            </div>

            {hasUnmatched && (
              <div className="bg-orange-50 border border-orange-200 rounded-lg p-3 space-y-3">
                <div className="flex items-start gap-2">
                  <span className="mt-0.5 text-orange-600">🤖</span>
                  <div>
                    <p className="text-sm font-semibold text-orange-800">
                      Unknown foods detected
                    </p>
                    <p className="text-xs text-orange-700">
                      Totals currently exclude these items. Ask the agent to locate nutrition data.
                    </p>
                  </div>
                </div>
                {unmatchedFoods.map((food, idx) => {
                  const agentState = agentResults.get(food.foodName)
                  const validation = agentState?.validation

                  const confidenceColor =
                    validation?.confidence === 'high'
                      ? 'text-green-700'
                      : validation?.confidence === 'medium'
                      ? 'text-orange-700'
                      : 'text-red-700'

                  return (
                    <div
                      key={`${food.foodName}-unmatched-${idx}`}
                      className="rounded-lg border border-orange-200 bg-white p-3 space-y-2"
                    >
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="text-sm font-semibold text-gray-800 capitalize">
                            {food.foodName}
                          </p>
                          <p className="text-xs text-gray-500">
                            {food.quantity} {food.unit}
                          </p>
                        </div>
                        <span className="text-xs bg-orange-100 text-orange-700 px-2 py-1 rounded">
                          Missing data
                        </span>
                      </div>

                      {!agentState && (
                        <button
                          onClick={() => handleFindFood(food)}
                          disabled={agentSearching === food.foodName}
                          className="text-xs px-3 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600 transition disabled:bg-gray-400"
                        >
                          {agentSearching === food.foodName
                            ? 'Searching...'
                            : 'Find with agent'}
                        </button>
                      )}

                      {agentState && agentState.loading && (
                        <p className="text-xs text-orange-600">
                          Agent is searching for reliable nutrition sources...
                        </p>
                      )}

                      {agentState && !agentState.loading && agentState.foodData && (
                        <div className="space-y-2 text-xs text-gray-700">
                          <div className="grid grid-cols-2 gap-x-3 gap-y-1">
                            <span className="text-gray-500">Serving size</span>
                            <span className="font-medium text-gray-800 text-right">
                              {agentState.foodData.servingSize}{' '}
                              {agentState.foodData.servingUnit}
                            </span>
                            <span className="text-gray-500">Calories</span>
                            <span className="font-medium text-gray-800 text-right">
                              {Math.round(agentState.foodData.calories)} kcal
                            </span>
                            <span className="text-gray-500">Protein</span>
                            <span className="font-medium text-gray-800 text-right">
                              {Math.round(agentState.foodData.protein)} g
                            </span>
                            <span className="text-gray-500">Carbs</span>
                            <span className="font-medium text-gray-800 text-right">
                              {Math.round(agentState.foodData.carbs)} g
                            </span>
                            <span className="text-gray-500">Fat</span>
                            <span className="font-medium text-gray-800 text-right">
                              {Math.round(agentState.foodData.fat)} g
                            </span>
                            <span className="text-gray-500">Fiber</span>
                            <span className="font-medium text-gray-800 text-right">
                              {Math.round(agentState.foodData.fiber)} g
                            </span>
                          </div>

                          {validation && (
                            <p className={`text-xs font-semibold ${confidenceColor}`}>
                              Confidence: {validation.confidence.toUpperCase()}
                            </p>
                          )}
                          {validation?.notes && (
                            <p className="text-[11px] text-gray-500">
                              {validation.notes}
                            </p>
                          )}
                          {validation?.sources && validation.sources.length > 0 && (
                            <p className="text-[11px] text-gray-400">
                              Sources: {validation.sources.join(', ')}
                            </p>
                          )}

                          <button
                            onClick={() => handleConfirmFood(food.foodName)}
                            disabled={agentSaving === food.foodName || loading}
                            className="w-full text-xs px-3 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition disabled:bg-gray-400"
                          >
                            {agentSaving === food.foodName ? 'Adding...' : 'Add to database'}
                          </button>
                        </div>
                      )}
                      {agentState && !agentState.loading && !agentState.foodData && (
                        <p className="text-xs text-red-600">
                          Could not find reliable nutrition data. Try rephrasing the food description.
                        </p>
                      )}
                    </div>
                  )
                })}
              </div>
            )}

            <div className="space-y-3">
              {currentResult.nutrition.foods.map((food, idx) => {
                const isUnmatched = !food.matched
                const cardClasses = isUnmatched
                  ? 'border border-orange-200 bg-orange-50'
                  : 'border border-green-200 bg-green-50'

                const confidence = typeof food.confidence === 'number' ? Math.round(food.confidence) : null
                const confidenceClasses =
                  confidence !== null
                    ? confidence >= 90
                      ? 'bg-green-100 text-green-700'
                      : confidence >= 70
                      ? 'bg-yellow-100 text-yellow-700'
                      : 'bg-red-100 text-red-700'
                    : ''

                return (
                  <div
                    key={`${food.foodName}-${idx}`}
                    className={`rounded-lg px-3 py-3 shadow-sm ${cardClasses}`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-medium capitalize text-gray-800">
                          {food.foodName}
                        </p>
                        <p className="text-xs text-gray-600">
                          {food.quantity} {food.unit}
                        </p>
                        {food.suggestedName && food.suggestedName !== food.foodName && (
                          <p className="text-xs text-blue-600 mt-1">
                            Suggested match: {food.suggestedName}
                          </p>
                        )}
                      </div>
                      <div className="text-right space-y-1">
                        {confidence !== null && !isUnmatched && (
                          <span className={`inline-block text-[11px] px-2 py-1 rounded ${confidenceClasses}`}>
                            {confidence}% match
                          </span>
                        )}
                        {isUnmatched ? (
                          <span className="inline-block text-[11px] px-2 py-1 rounded bg-orange-200 text-orange-800">
                            Needs attention
                          </span>
                        ) : null}
                      </div>
                    </div>

                    {isUnmatched ? (
                      <p className="text-xs text-orange-700 mt-2">
                        No nutrition data yet. Add it above and I&apos;ll refresh your totals.
                      </p>
                    ) : (
                      <div className="text-xs text-gray-600 mt-3">
                        {Math.round(food.calories)} kcal • {Math.round(food.protein)} g protein •{' '}
                        {Math.round(food.carbs)} g carbs • {Math.round(food.fat)} g fat •{' '}
                        {Math.round(food.fiber)} g fiber
                      </div>
                    )}
                  </div>
                )
              })}
            </div>

            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <div className="bg-blue-50 rounded-lg p-3 text-center">
                <p className="text-xs text-gray-600">Calories</p>
                <p className="text-lg font-semibold text-blue-700">
                  {Math.round(currentResult.nutrition.totals.calories)}
                </p>
                <p className="text-[11px] text-gray-500">kcal</p>
              </div>
              <div className="bg-purple-50 rounded-lg p-3 text-center">
                <p className="text-xs text-gray-600">Protein</p>
                <p className="text-lg font-semibold text-purple-700">
                  {Math.round(currentResult.nutrition.totals.protein)} g
                </p>
              </div>
              <div className="bg-yellow-50 rounded-lg p-3 text-center">
                <p className="text-xs text-gray-600">Carbs</p>
                <p className="text-lg font-semibold text-yellow-700">
                  {Math.round(currentResult.nutrition.totals.carbs)} g
                </p>
              </div>
              <div className="bg-red-50 rounded-lg p-3 text-center">
                <p className="text-xs text-gray-600">Fat</p>
                <p className="text-lg font-semibold text-red-700">
                  {Math.round(currentResult.nutrition.totals.fat)} g
                </p>
              </div>
              <div className="bg-green-50 rounded-lg p-3 text-center">
                <p className="text-xs text-gray-600">Fiber</p>
                <p className="text-lg font-semibold text-green-700">
                  {Math.round(currentResult.nutrition.totals.fiber)} g
                </p>
              </div>
            </div>

            {hasUnmatched && (
              <p className="text-xs text-orange-700 text-center">
                Resolve unknown foods before saving. Totals currently exclude them.
              </p>
            )}

            <button
              onClick={handleSaveMeal}
              disabled={saving || hasUnmatched || loading}
              className="w-full bg-green-600 text-white py-3 rounded-xl font-medium hover:bg-green-700 disabled:bg-gray-400 transition"
            >
              {hasUnmatched
                ? 'Resolve unknown foods to save'
                : saving
                ? 'Saving...'
                : 'Save meal to day'}
            </button>
          </div>
        )}

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg px-4 py-2">
            {error}
          </div>
        )}

        {loading && (
          <div className="text-sm text-gray-500 italic">
            Parsing meal details...
          </div>
        )}
      </div>

      <div className="border-t border-gray-200 p-4 bg-white">
        <div className="flex items-center gap-3">
          <input
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                handleSend()
              }
            }}
            placeholder="“Lunch: 1 cup Greek yogurt, salad, 1 tbsp chia”"
            className="flex-1 rounded-xl border border-gray-300 px-4 py-3 focus:outline-none focus:ring-2 focus:ring-green-500"
          />
          <button
            onClick={handleSend}
            disabled={loading}
            className="bg-green-500 text-white p-3 rounded-xl hover:bg-green-600 transition disabled:bg-gray-400"
          >
            <Send size={18} />
          </button>
        </div>
      </div>
    </div>
  )
}

function EndOfDayView({
  profile,
  summary,
  onBackHome,
}: {
  profile: Profile
  summary: DailySummary
  onBackHome: () => void
}) {
  return (
    <div className="flex flex-col h-full bg-gradient-to-b from-blue-50 to-white">
      <div className="bg-blue-500 text-white p-4 shadow-md flex justify-between items-center">
        <h2 className="font-bold text-lg">Daily Closeout</h2>
        <button
          onClick={onBackHome}
          className="bg-white text-blue-600 rounded-full px-4 py-2 text-sm font-medium hover:bg-blue-50 transition"
        >
          Back to dashboard
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-6 space-y-6">
        <div className="bg-white rounded-2xl shadow p-6">
          <h3 className="text-xl font-semibold text-gray-800 mb-2">
            Remaining targets
          </h3>
          <p className="text-sm text-gray-600 mb-4">
            Here&apos;s what you have left before hitting today&apos;s goal.
          </p>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3 text-center">
            {(['calories', 'protein', 'carbs', 'fat', 'fiber'] as const).map(
              (macro) => (
                <div
                  key={macro}
                  className="bg-blue-50 rounded-xl p-4 border border-blue-100"
                >
                  <p className="text-xs uppercase text-blue-600 tracking-wide">
                    {macro}
                  </p>
                  <p className="text-lg font-semibold text-blue-900">
                    {Math.round(summary.remaining[macro])}
                    {macro === 'calories' ? ' kcal' : 'g'}
                  </p>
                </div>
              )
            )}
          </div>
        </div>

        <div className="bg-white rounded-2xl shadow p-6 space-y-4">
          <div className="flex items-start gap-3">
            <Plus className="text-blue-500 mt-1" size={20} />
            <div>
              <h3 className="text-lg font-semibold text-gray-800">
                {summary.closingPlan.headline}
              </h3>
              <p className="text-sm text-gray-600">
                Pick the combo that fits your appetite tonight.
              </p>
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {summary.closingPlan.options.map((option, idx) => (
              <div
                key={`${option.title}-${idx}`}
                className="border border-blue-100 rounded-xl p-4 bg-blue-50"
              >
                <p className="font-semibold text-blue-800">{option.title}</p>
                <p className="text-sm text-blue-700 mt-1">{option.details}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-white rounded-2xl shadow p-6">
          <h3 className="text-lg font-semibold text-gray-800 mb-2">
            Today&apos;s recap
          </h3>
          <ul className="space-y-2 text-sm text-gray-700">
            <li>
              • Total intake: {Math.round(summary.totals.calories)} kcal with{' '}
              {Math.round(summary.totals.protein)}g protein.
            </li>
            <li>
              • Goal: {profile.dailyCalories} kcal &mdash; macro split{' '}
              {profile.dailyProtein}P / {profile.dailyCarbs}C /{' '}
              {profile.dailyFat}F / {profile.dailyFiber} fiber.
            </li>
          </ul>
        </div>
      </div>
    </div>
  )
}

export default function HomePage() {
  const [screen, setScreen] = useState<Screen>('loading')
  const [userId, setUserId] = useState<string | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [summary, setSummary] = useState<DailySummary | null>(null)
  const [loadingSummary, setLoadingSummary] = useState(false)

  const loadProfile = async (incomingUserId?: string) => {
    const id =
      incomingUserId ||
      userId ||
      (typeof window !== 'undefined'
        ? window.localStorage.getItem('nutritionUserId')
        : null)

    if (!id) {
      setScreen('onboarding')
      return
    }

    const response = await fetch(`/api/profile?userId=${id}`, {
      cache: 'no-store',
    })
    const data = await response.json()

    if (response.ok && data?.data?.profile) {
      const resultProfile = data.data.profile as Profile
      setProfile(resultProfile)
      setUserId(id)
      if (typeof window !== 'undefined') {
        window.localStorage.setItem('nutritionUserId', id)
      }
      setScreen('home')
      refreshSummary(id)
    } else {
      setScreen('onboarding')
    }
  }

  const refreshSummary = async (id = userId) => {
    if (!id) return
    setLoadingSummary(true)

    const response = await fetch(
      `/api/daily-summary?userId=${id}&date=${new Date().toISOString()}`,
      {
        cache: 'no-store',
      }
    )
    const data = await response.json()

    if (response.ok && data?.data) {
      setSummary(data.data)
    }

    setLoadingSummary(false)
  }

  useEffect(() => {
    loadProfile().catch((error) => {
      console.error('Failed to load profile', error)
      setScreen('onboarding')
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleOnboardingComplete = (result: { userId: string; profile: Profile }) => {
    setUserId(result.userId)
    setProfile(result.profile)
    if (typeof window !== 'undefined') {
      window.localStorage.setItem('nutritionUserId', result.userId)
    }
    setScreen('home')
    refreshSummary(result.userId)
  }

  const mainView = useMemo(() => {
    if (screen === 'onboarding' || (!profile && screen !== 'loading')) {
      return (
        <OnboardingForm
          onComplete={handleOnboardingComplete}
          loading={screen === 'loading'}
        />
      )
    }

    if (!profile || !userId) {
      return (
        <div className="min-h-screen flex items-center justify-center">
          <p className="text-gray-500">Loading your nutrition companion...</p>
        </div>
      )
    }

    if (screen === 'chat') {
      return (
        <ChatLogger
          userId={userId}
          profile={profile}
          onClose={() => setScreen('home')}
          onMealLogged={() => refreshSummary(userId)}
        />
      )
    }

    if (screen === 'endOfDay' && summary) {
      return (
        <EndOfDayView
          profile={profile}
          summary={summary}
          onBackHome={() => setScreen('home')}
        />
      )
    }

    return (
      <Dashboard
        profile={profile}
        summary={summary}
        onStartChat={() => setScreen('chat')}
        onEndDay={() => {
          refreshSummary(userId).then(() => setScreen('endOfDay'))
        }}
        onEditProfile={() => setScreen('onboarding')}
      />
    )
  }, [screen, profile, userId, summary])

  return (
    <div className="min-h-screen bg-gray-50">
      {loadingSummary && screen === 'home' && (
        <div className="absolute top-4 right-4 bg-white border border-green-200 shadow rounded-full px-4 py-2 text-sm text-green-700">
          Syncing latest meals...
        </div>
      )}
      {mainView}
    </div>
  )
}
