import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

const foods = [
  // Eggs
  {
    name: 'whole egg',
    brand: null,
    category: 'protein',
    servingSize: 1,
    servingUnit: 'piece',
    calories: 70,
    protein: 6,
    carbs: 0.5,
    fat: 5,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'egg white',
    brand: null,
    category: 'protein',
    servingSize: 1,
    servingUnit: 'piece',
    calories: 17,
    protein: 3.6,
    carbs: 0.2,
    fat: 0.1,
    fiber: 0,
    source: 'manual'
  },

  // Dairy
  {
    name: 'greek yogurt',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 130,
    protein: 23,
    carbs: 9,
    fat: 0.7,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'milk',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 103,
    protein: 8,
    carbs: 12,
    fat: 2.4,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'milk 2 percent',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 122,
    protein: 8,
    carbs: 12,
    fat: 4.8,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'milk whole',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 149,
    protein: 7.7,
    carbs: 12.3,
    fat: 7.9,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'milk skim',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 83,
    protein: 8.3,
    carbs: 12.5,
    fat: 0.2,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'milk almond unsweetened',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 39,
    protein: 1.5,
    carbs: 1.5,
    fat: 3.4,
    fiber: 0.5,
    source: 'manual'
  },
  {
    name: 'milk oat unsweetened',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 120,
    protein: 3,
    carbs: 16,
    fat: 5,
    fiber: 2,
    source: 'manual'
  },
  {
    name: 'milk soy unsweetened',
    brand: null,
    category: 'dairy',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 80,
    protein: 7,
    carbs: 4,
    fat: 4,
    fiber: 2,
    source: 'manual'
  },
  {
    name: 'paneer',
    brand: null,
    category: 'dairy',
    servingSize: 100,
    servingUnit: 'g',
    calories: 265,
    protein: 18,
    carbs: 3,
    fat: 20,
    fiber: 0,
    source: 'manual'
  },

  // Beverages
  {
    name: 'chai',
    brand: null,
    category: 'beverage',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 60,
    protein: 2,
    carbs: 12,
    fat: 0,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'black coffee',
    brand: null,
    category: 'beverage',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 2,
    protein: 0.3,
    carbs: 0,
    fat: 0,
    fiber: 0,
    source: 'manual'
  },

  // Seeds & Nuts
  {
    name: 'chia seeds',
    brand: null,
    category: 'seeds',
    servingSize: 1,
    servingUnit: 'tbsp',
    calories: 58,
    protein: 2,
    carbs: 5,
    fat: 3.7,
    fiber: 4.1,
    source: 'manual'
  },
  {
    name: 'almonds',
    brand: null,
    category: 'nuts',
    servingSize: 10,
    servingUnit: 'piece',
    calories: 69,
    protein: 2.5,
    carbs: 2.5,
    fat: 6,
    fiber: 1.2,
    source: 'manual'
  },
  {
    name: 'peanuts',
    brand: null,
    category: 'nuts',
    servingSize: 28,
    servingUnit: 'g',
    calories: 161,
    protein: 7.3,
    carbs: 4.6,
    fat: 14,
    fiber: 2.4,
    source: 'manual'
  },

  // Grains & Cereals
  {
    name: 'oats',
    brand: null,
    category: 'grain',
    servingSize: 0.5,
    servingUnit: 'cup',
    calories: 150,
    protein: 5,
    carbs: 27,
    fat: 2.5,
    fiber: 4,
    source: 'manual'
  },
  {
    name: 'rice',
    brand: null,
    category: 'grain',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 206,
    protein: 4.3,
    carbs: 45,
    fat: 0.4,
    fiber: 0.6,
    source: 'manual'
  },
  {
    name: 'roti',
    brand: null,
    category: 'grain',
    servingSize: 1,
    servingUnit: 'piece',
    calories: 71,
    protein: 2.5,
    carbs: 15,
    fat: 0.4,
    fiber: 2.7,
    source: 'manual'
  },
  {
    name: 'quinoa',
    brand: null,
    category: 'grain',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 222,
    protein: 8,
    carbs: 39,
    fat: 3.6,
    fiber: 5,
    source: 'manual'
  },

  // Legumes
  {
    name: 'chickpeas',
    brand: null,
    category: 'legume',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 269,
    protein: 14.5,
    carbs: 45,
    fat: 4.2,
    fiber: 12.5,
    source: 'manual'
  },
  {
    name: 'moong dal',
    brand: null,
    category: 'legume',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 212,
    protein: 14.2,
    carbs: 38.7,
    fat: 0.8,
    fiber: 15.4,
    source: 'manual'
  },
  {
    name: 'rajma',
    brand: null,
    category: 'legume',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 225,
    protein: 15,
    carbs: 40,
    fat: 0.9,
    fiber: 13,
    source: 'manual'
  },

  // Vegetables
  {
    name: 'spinach',
    brand: null,
    category: 'vegetable',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 7,
    protein: 0.9,
    carbs: 1.1,
    fat: 0.1,
    fiber: 0.7,
    source: 'manual'
  },
  {
    name: 'broccoli',
    brand: null,
    category: 'vegetable',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 55,
    protein: 3.7,
    carbs: 11,
    fat: 0.6,
    fiber: 2.4,
    source: 'manual'
  },
  {
    name: 'salad',
    brand: null,
    category: 'vegetable',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 15,
    protein: 1,
    carbs: 3,
    fat: 0.2,
    fiber: 1.5,
    source: 'manual'
  },

  // Fruits
  {
    name: 'banana',
    brand: null,
    category: 'fruit',
    servingSize: 1,
    servingUnit: 'piece',
    calories: 105,
    protein: 1.3,
    carbs: 27,
    fat: 0.4,
    fiber: 3.1,
    source: 'manual'
  },
  {
    name: 'apple',
    brand: null,
    category: 'fruit',
    servingSize: 1,
    servingUnit: 'piece',
    calories: 95,
    protein: 0.5,
    carbs: 25,
    fat: 0.3,
    fiber: 4.4,
    source: 'manual'
  },

  // Protein Sources
  {
    name: 'chicken breast',
    brand: null,
    category: 'protein',
    servingSize: 100,
    servingUnit: 'g',
    calories: 165,
    protein: 31,
    carbs: 0,
    fat: 3.6,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'tofu',
    brand: null,
    category: 'protein',
    servingSize: 100,
    servingUnit: 'g',
    calories: 76,
    protein: 8,
    carbs: 1.9,
    fat: 4.8,
    fiber: 0.3,
    source: 'manual'
  },

  // Protein Supplements
  {
    name: 'barebells protein bar',
    brand: 'Barebells',
    category: 'supplement',
    servingSize: 1,
    servingUnit: 'bar',
    calories: 200,
    protein: 20,
    carbs: 17,
    fat: 8,
    fiber: 5,
    source: 'manual'
  },
  {
    name: 'whey protein',
    brand: null,
    category: 'supplement',
    servingSize: 1,
    servingUnit: 'scoop',
    calories: 120,
    protein: 24,
    carbs: 3,
    fat: 1.5,
    fiber: 0,
    source: 'manual'
  },

  // Miscellaneous
  {
    name: 'peanut butter',
    brand: null,
    category: 'spread',
    servingSize: 1,
    servingUnit: 'tbsp',
    calories: 96,
    protein: 4,
    carbs: 3.6,
    fat: 8.2,
    fiber: 0.9,
    source: 'manual'
  },
  {
    name: 'honey',
    brand: null,
    category: 'sweetener',
    servingSize: 1,
    servingUnit: 'tbsp',
    calories: 64,
    protein: 0.1,
    carbs: 17,
    fat: 0,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'olive oil',
    brand: null,
    category: 'oil',
    servingSize: 1,
    servingUnit: 'tbsp',
    calories: 119,
    protein: 0,
    carbs: 0,
    fat: 13.5,
    fiber: 0,
    source: 'manual'
  },
  {
    name: 'edamame',
    brand: null,
    category: 'legume',
    servingSize: 1,
    servingUnit: 'cup',
    calories: 150,
    protein: 13,
    carbs: 13,
    fat: 5,
    fiber: 8,
    source: 'manual'
  }
]

async function main() {
  console.log('🌱 Starting database seed...')

  // Clear existing data (respect relational order)
  await prisma.foodEntry.deleteMany()
  await prisma.meal.deleteMany()
  await prisma.profile.deleteMany()
  await prisma.user.deleteMany()
  await prisma.food.deleteMany()

  console.log('🗑️  Cleared existing data')

  // Create demo user + profile for local testing
  const demoUser = await prisma.user.create({
    data: {
      name: 'Demo User',
      email: 'demo@nutrition.app',
    },
  })

  await prisma.profile.create({
    data: {
      userId: demoUser.id,
      heightCm: 170,
      weightKg: 68,
      age: 32,
      gender: 'female',
      activityLevel: 'moderate',
      goal: 'moderate_loss',
      dietPreference: 'veg_eggs',
      mealPattern: '3_meals',
      dailyCalories: 1700,
      dailyProtein: 150,
      dailyCarbs: 120,
      dailyFat: 60,
      dailyFiber: 30,
    },
  })

  // Seed foods
  for (const food of foods) {
    await prisma.food.create({
      data: food
    })
  }

  console.log(`✅ Seeded ${foods.length} food items`)
  console.log('🎉 Database seed completed!')
}

main()
  .catch((e) => {
    console.error('❌ Seed error:', e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })
