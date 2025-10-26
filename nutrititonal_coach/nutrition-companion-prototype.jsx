import React, { useState } from 'react';
import { Send, Plus, TrendingUp, Calendar, Settings, Home, MessageSquare, BarChart3, Check, X } from 'lucide-react';

const NutritionCompanionPrototype = () => {
  const [screen, setScreen] = useState('home');
  const [messages, setMessages] = useState([
    { type: 'assistant', text: "Good morning! Ready to log your breakfast? 🌅" }
  ]);
  const [inputText, setInputText] = useState('');
  
  // User profile data
  const userProfile = {
    name: "Alex",
    goal: "Moderate Loss",
    dailyTarget: {
      calories: 1700,
      protein: 150,
      carbs: 120,
      fat: 60,
      fiber: 30
    },
    current: {
      calories: 750,
      protein: 68,
      carbs: 54,
      fat: 28,
      fiber: 12
    }
  };

  const getRemainingNutrients = () => ({
    calories: userProfile.dailyTarget.calories - userProfile.current.calories,
    protein: userProfile.dailyTarget.protein - userProfile.current.protein,
    carbs: userProfile.dailyTarget.carbs - userProfile.current.carbs,
    fat: userProfile.dailyTarget.fat - userProfile.current.fat,
    fiber: userProfile.dailyTarget.fiber - userProfile.current.fiber
  });

  const getProgressPercentage = (current, target) => {
    return Math.min((current / target) * 100, 100);
  };

  const getProgressColor = (percentage) => {
    if (percentage >= 90) return 'bg-red-500';
    if (percentage >= 70) return 'bg-orange-500';
    return 'bg-green-500';
  };

  const handleSendMessage = () => {
    if (!inputText.trim()) return;

    const newMessages = [...messages, { type: 'user', text: inputText }];
    
    // Simulate AI response
    setTimeout(() => {
      let response = "";
      if (inputText.toLowerCase().includes('breakfast') || inputText.toLowerCase().includes('egg')) {
        response = "✅ Breakfast logged!\n\n1 egg + 3 egg whites + 1 chai\n\n📊 Added: 210 kcal, 23g protein, 17g carbs, 3g fat\n\nYou have 740 kcal and 59g protein left for today. Great start! 💪";
      } else if (inputText.toLowerCase().includes('lunch') || inputText.toLowerCase().includes('yogurt')) {
        response = "✅ Lunch logged!\n\n1 cup Greek yogurt + salad + 1 tbsp chia seeds\n\n📊 Added: 285 kcal, 28g protein, 22g carbs, 12g fat, 8g fiber\n\nRemaining: 665 kcal, 54g protein, 44g carbs. Looking good!";
      } else if (inputText.toLowerCase().includes('done') || inputText.toLowerCase().includes('finish')) {
        setScreen('endOfDay');
        return;
      } else {
        response = "I can help you log that! Could you specify the portion size? For example: '1 cup', '2 slices', or '100g'";
      }
      
      setMessages(prev => [...prev, { type: 'assistant', text: response }]);
    }, 500);

    setMessages(newMessages);
    setInputText('');
  };

  const NutrientBar = ({ label, current, target, unit = 'g' }) => {
    const percentage = getProgressPercentage(current, target);
    const colorClass = getProgressColor(percentage);
    const remaining = target - current;

    return (
      <div className="mb-4">
        <div className="flex justify-between items-center mb-1">
          <span className="font-medium text-gray-700">{label}</span>
          <span className="text-sm text-gray-600">
            {current}{unit} / {target}{unit}
          </span>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
          <div 
            className={`h-full ${colorClass} transition-all duration-300`}
            style={{ width: `${percentage}%` }}
          />
        </div>
        <div className="text-right mt-1">
          <span className={`text-xs ${remaining > 0 ? 'text-green-600' : 'text-red-600'}`}>
            {remaining > 0 ? `+${remaining}${unit} left` : `${Math.abs(remaining)}${unit} over`}
          </span>
        </div>
      </div>
    );
  };

  // Home Screen
  const HomeScreen = () => {
    const remaining = getRemainingNutrients();
    
    return (
      <div className="flex flex-col h-full bg-gradient-to-b from-green-50 to-white">
        {/* Header */}
        <div className="bg-white shadow-sm p-4">
          <div className="flex justify-between items-center">
            <div>
              <h1 className="text-2xl font-bold text-gray-800">Hey {userProfile.name}! 👋</h1>
              <p className="text-sm text-gray-600">Saturday, October 25</p>
            </div>
            <button className="p-2 hover:bg-gray-100 rounded-full">
              <Settings size={24} className="text-gray-600" />
            </button>
          </div>
        </div>

        {/* Nutrient Summary Card */}
        <div className="p-4">
          <div className="bg-white rounded-2xl shadow-lg p-6 mb-4">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-lg font-bold text-gray-800">Today's Progress</h2>
              <span className="text-sm text-gray-500">44% complete</span>
            </div>
            
            {/* Calories - Main Focus */}
            <div className="bg-gradient-to-r from-green-100 to-green-50 rounded-xl p-4 mb-4">
              <div className="flex justify-between items-center">
                <div>
                  <p className="text-sm text-gray-600">Calories</p>
                  <p className="text-3xl font-bold text-gray-800">{userProfile.current.calories}</p>
                  <p className="text-sm text-green-600">of {userProfile.dailyTarget.calories} kcal</p>
                </div>
                <div className="text-right">
                  <p className="text-2xl font-bold text-green-600">{remaining.calories}</p>
                  <p className="text-xs text-gray-600">remaining</p>
                </div>
              </div>
            </div>

            {/* Macros */}
            <div className="space-y-3">
              <NutrientBar label="Protein" current={userProfile.current.protein} target={userProfile.dailyTarget.protein} />
              <NutrientBar label="Carbs" current={userProfile.current.carbs} target={userProfile.dailyTarget.carbs} />
              <NutrientBar label="Fat" current={userProfile.current.fat} target={userProfile.dailyTarget.fat} />
              <NutrientBar label="Fiber" current={userProfile.current.fiber} target={userProfile.dailyTarget.fiber} />
            </div>
          </div>

          {/* Quick Actions */}
          <div className="bg-white rounded-2xl shadow-lg p-4">
            <h3 className="font-semibold text-gray-700 mb-3">Quick Actions</h3>
            <div className="grid grid-cols-2 gap-3">
              <button 
                onClick={() => setScreen('chat')}
                className="bg-green-500 text-white rounded-xl p-4 flex items-center justify-center space-x-2 hover:bg-green-600 transition"
              >
                <MessageSquare size={20} />
                <span className="font-medium">Log Meal</span>
              </button>
              <button 
                onClick={() => setScreen('endOfDay')}
                className="bg-blue-500 text-white rounded-xl p-4 flex items-center justify-center space-x-2 hover:bg-blue-600 transition"
              >
                <Check size={20} />
                <span className="font-medium">End Day</span>
              </button>
            </div>
          </div>

          {/* Smart Suggestions */}
          <div className="mt-4 bg-orange-50 border-l-4 border-orange-500 rounded-lg p-4">
            <p className="text-sm font-medium text-orange-800">💡 Smart Tip</p>
            <p className="text-sm text-orange-700 mt-1">
              You've used 47% of your fat allowance. Keep dinner light on oils and nuts!
            </p>
          </div>
        </div>
      </div>
    );
  };

  // Chat Screen
  const ChatScreen = () => {
    return (
      <div className="flex flex-col h-full bg-white">
        {/* Header */}
        <div className="bg-green-500 text-white p-4 shadow-md">
          <div className="flex items-center space-x-3">
            <button onClick={() => setScreen('home')} className="hover:bg-green-600 rounded-full p-1">
              <X size={24} />
            </button>
            <div>
              <h2 className="font-bold text-lg">Food Logger</h2>
              <p className="text-xs text-green-100">Natural language • Voice supported</p>
            </div>
          </div>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.map((msg, idx) => (
            <div key={idx} className={`flex ${msg.type === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div className={`max-w-[80%] rounded-2xl p-4 ${
                msg.type === 'user' 
                  ? 'bg-green-500 text-white rounded-br-none' 
                  : 'bg-gray-100 text-gray-800 rounded-bl-none'
              }`}>
                <p className="text-sm whitespace-pre-line">{msg.text}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Quick Suggestions */}
        <div className="px-4 py-2 bg-gray-50 border-t">
          <div className="flex gap-2 overflow-x-auto pb-2">
            {['Breakfast: 1 egg, 3 whites, 1 chai', 'Lunch: Greek yogurt, salad', "I'm done for today"].map((suggestion, idx) => (
              <button
                key={idx}
                onClick={() => setInputText(suggestion)}
                className="px-3 py-2 bg-white border border-gray-300 rounded-full text-xs whitespace-nowrap hover:bg-gray-100 transition"
              >
                {suggestion}
              </button>
            ))}
          </div>
        </div>

        {/* Input */}
        <div className="p-4 bg-white border-t">
          <div className="flex items-center space-x-2">
            <input
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              onKeyPress={(e) => e.key === 'Enter' && handleSendMessage()}
              placeholder="Type your meal... e.g., '2 eggs, 1 toast'"
              className="flex-1 border border-gray-300 rounded-full px-4 py-3 focus:outline-none focus:border-green-500"
            />
            <button
              onClick={handleSendMessage}
              className="bg-green-500 text-white rounded-full p-3 hover:bg-green-600 transition"
            >
              <Send size={20} />
            </button>
          </div>
        </div>
      </div>
    );
  };

  // End of Day Screen
  const EndOfDayScreen = () => {
    const remaining = getRemainingNutrients();
    
    return (
      <div className="flex flex-col h-full bg-gradient-to-b from-blue-50 to-white overflow-y-auto">
        {/* Header */}
        <div className="bg-blue-500 text-white p-6 shadow-md">
          <button onClick={() => setScreen('home')} className="mb-3 hover:bg-blue-600 rounded-full p-1 inline-block">
            <X size={24} />
          </button>
          <h2 className="font-bold text-2xl">End of Day Analysis</h2>
          <p className="text-blue-100 text-sm mt-1">Let's balance your nutrients</p>
        </div>

        <div className="p-4 space-y-4">
          {/* Gap Analysis */}
          <div className="bg-white rounded-2xl shadow-lg p-6">
            <h3 className="font-bold text-lg text-gray-800 mb-4">📊 Nutrient Gaps</h3>
            
            <div className="space-y-3">
              {remaining.protein > 0 && (
                <div className="flex items-center justify-between p-3 bg-orange-50 rounded-lg">
                  <span className="text-gray-700">Protein</span>
                  <span className="font-bold text-orange-600">+{remaining.protein}g short</span>
                </div>
              )}
              {remaining.fiber > 0 && (
                <div className="flex items-center justify-between p-3 bg-orange-50 rounded-lg">
                  <span className="text-gray-700">Fiber</span>
                  <span className="font-bold text-orange-600">+{remaining.fiber}g short</span>
                </div>
              )}
              {remaining.carbs > 0 && (
                <div className="flex items-center justify-between p-3 bg-green-50 rounded-lg">
                  <span className="text-gray-700">Carbs</span>
                  <span className="font-bold text-green-600">+{remaining.carbs}g left</span>
                </div>
              )}
            </div>
          </div>

          {/* AI Suggestions */}
          <div className="bg-white rounded-2xl shadow-lg p-6">
            <h3 className="font-bold text-lg text-gray-800 mb-4">🤖 Smart Suggestions</h3>
            <p className="text-sm text-gray-600 mb-4">
              Based on your gaps, here's what would perfectly balance your day:
            </p>

            {/* Suggestion Cards */}
            <div className="space-y-3">
              <div className="border-2 border-green-500 rounded-xl p-4 bg-green-50">
                <div className="flex justify-between items-start mb-3">
                  <div>
                    <h4 className="font-semibold text-gray-800">Recommended Close-out</h4>
                    <p className="text-xs text-gray-600 mt-1">Perfect macro balance</p>
                  </div>
                  <span className="bg-green-500 text-white text-xs px-3 py-1 rounded-full font-medium">
                    Best Match
                  </span>
                </div>
                
                <div className="space-y-2 mb-4">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-700">• ½ Barebells protein bar</span>
                    <span className="text-gray-600">100 kcal</span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-700">• ½ cup Greek yogurt</span>
                    <span className="text-gray-600">80 kcal</span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-700">• 1 tbsp chia seeds</span>
                    <span className="text-gray-600">70 kcal</span>
                  </div>
                </div>

                <div className="bg-white rounded-lg p-3 mb-3">
                  <div className="grid grid-cols-4 gap-2 text-center text-xs">
                    <div>
                      <p className="text-gray-600">Protein</p>
                      <p className="font-bold text-green-600">+22g</p>
                    </div>
                    <div>
                      <p className="text-gray-600">Carbs</p>
                      <p className="font-bold text-green-600">+18g</p>
                    </div>
                    <div>
                      <p className="text-gray-600">Fiber</p>
                      <p className="font-bold text-green-600">+7g</p>
                    </div>
                    <div>
                      <p className="text-gray-600">Total</p>
                      <p className="font-bold text-gray-800">250 kcal</p>
                    </div>
                  </div>
                </div>

                <button className="w-full bg-green-500 text-white rounded-lg py-3 font-semibold hover:bg-green-600 transition">
                  ✓ Add to Today's Plan
                </button>
              </div>

              {/* Alternative Option */}
              <div className="border border-gray-300 rounded-xl p-4 bg-gray-50">
                <div className="flex justify-between items-start mb-3">
                  <div>
                    <h4 className="font-semibold text-gray-800">Alternative Option</h4>
                    <p className="text-xs text-gray-600 mt-1">More fiber-focused</p>
                  </div>
                </div>
                
                <div className="space-y-2 mb-3">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-700">• 1 cup edamame</span>
                    <span className="text-gray-600">150 kcal</span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-700">• Small handful almonds</span>
                    <span className="text-gray-600">100 kcal</span>
                  </div>
                </div>

                <button className="w-full bg-gray-300 text-gray-700 rounded-lg py-2 font-medium hover:bg-gray-400 transition">
                  View Details
                </button>
              </div>
            </div>
          </div>

          {/* Insights */}
          <div className="bg-purple-50 border-l-4 border-purple-500 rounded-lg p-4">
            <p className="text-sm font-medium text-purple-800">💜 Focus Insight</p>
            <p className="text-sm text-purple-700 mt-1">
              This protein boost will help sustain your morning energy tomorrow!
            </p>
          </div>
        </div>
      </div>
    );
  };

  // Onboarding Screen
  const OnboardingScreen = () => {
    const [step, setStep] = useState(1);
    
    return (
      <div className="flex flex-col h-full bg-gradient-to-b from-green-50 to-white p-6 overflow-y-auto">
        <div className="max-w-md mx-auto w-full">
          <div className="text-center mb-8">
            <div className="text-6xl mb-4">🥗</div>
            <h1 className="text-3xl font-bold text-gray-800 mb-2">Welcome!</h1>
            <p className="text-gray-600">Let's personalize your nutrition journey</p>
          </div>

          <div className="bg-white rounded-2xl shadow-lg p-6 mb-6">
            <div className="flex justify-between mb-6">
              {[1, 2, 3, 4].map((num) => (
                <div key={num} className={`w-1/4 h-2 rounded-full mx-1 ${num <= step ? 'bg-green-500' : 'bg-gray-200'}`} />
              ))}
            </div>

            {step === 1 && (
              <div className="space-y-4">
                <h3 className="font-bold text-xl text-gray-800">Basic Info</h3>
                <input type="number" placeholder="Age" className="w-full border rounded-lg p-3" />
                <input type="number" placeholder="Height (cm)" className="w-full border rounded-lg p-3" />
                <input type="number" placeholder="Weight (kg)" className="w-full border rounded-lg p-3" />
                <select className="w-full border rounded-lg p-3">
                  <option>Gender</option>
                  <option>Male</option>
                  <option>Female</option>
                  <option>Other</option>
                </select>
              </div>
            )}

            {step === 2 && (
              <div className="space-y-4">
                <h3 className="font-bold text-xl text-gray-800">Activity & Diet</h3>
                <select className="w-full border rounded-lg p-3">
                  <option>Activity Level</option>
                  <option>Sedentary (office job)</option>
                  <option>Lightly active (1-3 days/week)</option>
                  <option>Moderately active (3-5 days/week)</option>
                  <option>Very active (6-7 days/week)</option>
                </select>
                <select className="w-full border rounded-lg p-3">
                  <option>Diet Preference</option>
                  <option>Vegetarian</option>
                  <option>Vegetarian + Eggs</option>
                  <option>Non-vegetarian</option>
                </select>
              </div>
            )}

            {step === 3 && (
              <div className="space-y-4">
                <h3 className="font-bold text-xl text-gray-800">Your Goal</h3>
                <div className="space-y-3">
                  {['Maintain Weight', 'Moderate Loss (0.5 kg/week)', 'Aggressive Loss (1 kg/week)'].map((goal) => (
                    <button key={goal} className="w-full border-2 border-gray-300 rounded-xl p-4 hover:border-green-500 hover:bg-green-50 transition text-left">
                      <p className="font-semibold text-gray-800">{goal}</p>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {step === 4 && (
              <div className="space-y-4">
                <h3 className="font-bold text-xl text-gray-800">Your Daily Targets</h3>
                <div className="bg-green-50 rounded-xl p-4 space-y-3">
                  <div className="flex justify-between">
                    <span className="text-gray-700">Calories</span>
                    <span className="font-bold text-gray-800">1,700 kcal</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-700">Protein</span>
                    <span className="font-bold text-gray-800">150g</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-700">Carbs</span>
                    <span className="font-bold text-gray-800">120g</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-700">Fat</span>
                    <span className="font-bold text-gray-800">60g</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-700">Fiber</span>
                    <span className="font-bold text-gray-800">30g</span>
                  </div>
                </div>
                <p className="text-sm text-gray-600 text-center">Optimized for focus, energy, and sustainable weight management</p>
              </div>
            )}
          </div>

          <button 
            onClick={() => step < 4 ? setStep(step + 1) : setScreen('home')}
            className="w-full bg-green-500 text-white rounded-xl py-4 font-bold hover:bg-green-600 transition"
          >
            {step < 4 ? 'Continue' : 'Start Tracking!'}
          </button>
        </div>
      </div>
    );
  };

  // Bottom Navigation
  const BottomNav = () => {
    if (screen === 'onboarding') return null;
    
    return (
      <div className="bg-white border-t border-gray-200 px-6 py-3 flex justify-around items-center shadow-lg">
        <button 
          onClick={() => setScreen('home')}
          className={`flex flex-col items-center space-y-1 ${screen === 'home' ? 'text-green-500' : 'text-gray-400'}`}
        >
          <Home size={24} />
          <span className="text-xs font-medium">Home</span>
        </button>
        <button 
          onClick={() => setScreen('chat')}
          className={`flex flex-col items-center space-y-1 ${screen === 'chat' ? 'text-green-500' : 'text-gray-400'}`}
        >
          <MessageSquare size={24} />
          <span className="text-xs font-medium">Log</span>
        </button>
        <button className="flex flex-col items-center space-y-1 text-gray-400">
          <BarChart3 size={24} />
          <span className="text-xs font-medium">Stats</span>
        </button>
        <button className="flex flex-col items-center space-y-1 text-gray-400">
          <Calendar size={24} />
          <span className="text-xs font-medium">History</span>
        </button>
      </div>
    );
  };

  return (
    <div className="w-full h-screen bg-gray-50 flex items-center justify-center">
      <div className="w-full max-w-md h-full bg-white shadow-2xl flex flex-col relative">
        {/* Screen Content */}
        <div className="flex-1 overflow-hidden">
          {screen === 'onboarding' && <OnboardingScreen />}
          {screen === 'home' && <HomeScreen />}
          {screen === 'chat' && <ChatScreen />}
          {screen === 'endOfDay' && <EndOfDayScreen />}
        </div>

        {/* Bottom Navigation */}
        <BottomNav />

        {/* Demo Controls */}
        <div className="absolute top-2 left-2 bg-black bg-opacity-70 text-white text-xs px-3 py-1 rounded-full z-50">
          Demo Mode
        </div>
      </div>
    </div>
  );
};

export default NutritionCompanionPrototype;