# Food Parsing POC

Proof of concept for AI-powered natural language food parsing using OpenAI + PostgreSQL storage.

## Overview

This POC demonstrates the core technology for a conversational nutrition companion app. It validates:

- **Natural language food parsing** using OpenAI API
- **Macro calculation** from parsed food entries
- **Database storage** with PostgreSQL (Supabase)
- **End-to-end flow** from text input to stored meal data

## Tech Stack

- **Frontend**: Next.js 15, React, TypeScript, TailwindCSS
- **Backend**: Next.js API Routes
- **Database**: PostgreSQL (Supabase) + Prisma ORM
- **AI**: OpenAI GPT-4 for food parsing
- **Validation**: Zod

## Features

- Parse natural language input (e.g., "2 eggs, 1 chai, 3 egg whites")
- Extract food items, quantities, and units
- Look up nutrition data from food database
- Calculate total macros (calories, protein, carbs, fat, fiber)
- Store meals and food entries to database
- Display parsed results in UI

## Setup

### Prerequisites

- Node.js 18+ installed
- Supabase account (free tier)
- OpenAI API key

### Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd food-parsing-poc
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
```

Edit `.env` and add your credentials:
- `DATABASE_URL`: Get from Supabase Dashboard > Settings > Database > Connection String
- `OPENAI_API_KEY`: Get from https://platform.openai.com/api-keys

4. Set up the database:
```bash
npx prisma migrate dev --name init
npx prisma db seed  # Seed with common foods (including milk variants)
```

5. Generate Prisma Client:
```bash
npx prisma generate
```

6. Run the development server:
```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to test the POC.

## Database Schema

- **Food**: Individual food items with nutrition data per serving
- **Meal**: Logged meals with raw user input
- **FoodEntry**: Individual food items within a meal

## Project Structure

```
food-parsing-poc/
├── app/
│   ├── api/
│   │   ├── parse-food/    # OpenAI parsing endpoint
│   │   └── meals/         # Meal storage endpoints
│   └── page.tsx           # Test UI
├── lib/
│   ├── openai.ts         # OpenAI food parsing service
│   ├── nutrition.ts      # Macro calculation service
│   └── prisma.ts         # Prisma client singleton
├── prisma/
│   ├── schema.prisma     # Database schema
│   └── seed.ts           # Seed data
└── README.md
```

## Usage

1. Enter natural language food input (e.g., "1 cup Greek yogurt, 1 tbsp chia seeds")
2. Click "Parse Food"
3. View parsed food items with calculated macros
4. Save to database as a meal

## Next Steps

- [ ] Add fuzzy food matching for typos
- [ ] Implement voice input
- [ ] Build daily tracking dashboard
- [ ] Add end-of-day nutrient gap analysis
- [ ] Integrate with full nutrition companion app

## License

MIT
