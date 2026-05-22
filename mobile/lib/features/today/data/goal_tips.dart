// Goal-aware tip selection. Pure functions, no Flutter dependencies, so they
// can be unit tested in isolation.

typedef Tip = ({String emoji, String title, String body});

const fitnessTips = <Tip>[
  (
    emoji: '📅',
    title: 'Schedule like a meeting',
    body:
        'Put workouts on your calendar. Researchers found this triples follow-through.',
  ),
  (
    emoji: '🏃',
    title: 'Two-minute rule',
    body:
        'Lacking motivation? Just put on the shoes and walk out. Momentum does the rest.',
  ),
  (
    emoji: '🧘',
    title: 'Recover deliberately',
    body:
        'Sleep and rest days are when adaptation happens — not the workout itself.',
  ),
  (
    emoji: '📈',
    title: 'Track one number',
    body:
        'Reps, miles, or minutes — one metric you can beat next week beats vague effort.',
  ),
];

const learningTips = <Tip>[
  (
    emoji: '🔁',
    title: 'Spaced repetition',
    body:
        'Review material 1 day, 3 days, 7 days, 30 days after learning. Locks it in.',
  ),
  (
    emoji: '✍️',
    title: 'Teach to learn',
    body:
        'Explain what you learned in your own words. If you can\'t, you don\'t know it yet.',
  ),
  (
    emoji: '🍅',
    title: 'Pomodoro for study',
    body:
        '25 min focused study + 5 min break. Four cycles, then a longer rest.',
  ),
  (
    emoji: '🎯',
    title: 'Active over passive',
    body:
        'Solving problems beats re-reading. Generate questions, then answer them.',
  ),
];

const financeTips = <Tip>[
  (
    emoji: '💸',
    title: 'Pay yourself first',
    body:
        'Automate savings on payday. What you don\'t see, you don\'t spend.',
  ),
  (
    emoji: '📊',
    title: 'Know your number',
    body:
        'Track one metric weekly — net worth, savings rate, or spending. Awareness moves it.',
  ),
  (
    emoji: '🚫',
    title: '24-hour rule',
    body:
        'For non-essential purchases over \$50, wait a day. Most "wants" fade.',
  ),
  (
    emoji: '🏗️',
    title: 'Skill > stocks',
    body:
        'Your biggest financial asset is your earning power. Invest in skills first.',
  ),
];

const careerTips = <Tip>[
  (
    emoji: '🎯',
    title: 'Output, not hours',
    body:
        'Define what "done" looks like before you start. Vague goals stay incomplete.',
  ),
  (
    emoji: '📅',
    title: 'Weekly 1:1 with yourself',
    body:
        '30 min every Friday to review wins, blocks, and next week\'s focus.',
  ),
  (
    emoji: '🤝',
    title: 'Build before you need',
    body:
        'Network when you don\'t need anything. Relationships compound over years.',
  ),
  (
    emoji: '📝',
    title: 'Document wins weekly',
    body:
        'Keep a "brag doc". Promotions and reviews need evidence, not memory.',
  ),
];

const mindfulnessTips = <Tip>[
  (
    emoji: '🌬️',
    title: 'One minute breath',
    body:
        '5 deep breaths reset your nervous system. Cheaper than coffee, more effective.',
  ),
  (
    emoji: '📵',
    title: 'Phone-free morning',
    body:
        'First 30 min of your day without a screen. Sets your mind, not your inbox.',
  ),
  (
    emoji: '🚶',
    title: 'Walk without a podcast',
    body:
        '10 silent minutes a day. Your best ideas come when your brain stops consuming.',
  ),
  (
    emoji: '📓',
    title: 'Three lines a night',
    body:
        'Journaling 3 lines before bed beats 3 pages on the weekend. Consistency wins.',
  ),
];

const creativeTips = <Tip>[
  (
    emoji: '🚪',
    title: 'Show up, ship daily',
    body:
        'Creative work compounds. A bad draft daily beats a perfect draft monthly.',
  ),
  (
    emoji: '🎨',
    title: 'Steal like an artist',
    body:
        'Originality is recombination. Study what you love, then remix it.',
  ),
  (
    emoji: '⏳',
    title: 'Constraints over freedom',
    body:
        'Tight scope unlocks creativity. "Anything" is harder than "this specific thing".',
  ),
  (
    emoji: '🌊',
    title: 'Quantity → quality',
    body:
        'Make 100 of something. The first 10 are practice, the last 10 are art.',
  ),
];

const genericTips = <Tip>[
  (
    emoji: '🐸',
    title: 'Eat the frog',
    body: 'Do your hardest task first — your focus is strongest in the morning.',
  ),
  (
    emoji: '🎯',
    title: 'Rule of 3',
    body: 'Pick 3 tasks that would make today a win. Focus on those.',
  ),
  (
    emoji: '🧱',
    title: 'Block your time',
    body: 'Block 90 minutes for deep work. Protect it like a meeting.',
  ),
  (
    emoji: '⏰',
    title: 'Set a time',
    body: 'Setting a specific time for a task doubles your follow-through.',
  ),
  (
    emoji: '📦',
    title: 'Batch similar tasks',
    body: 'Group emails, messages, and admin into one block. Saves 40 min/day.',
  ),
  (
    emoji: '⚡',
    title: 'Match your energy',
    body: 'Deep work when fresh. Routine tasks when tired.',
  ),
  (
    emoji: '🔬',
    title: 'One thing at a time',
    body: 'Every context switch costs 23 min of refocus. Single-task for flow.',
  ),
  (
    emoji: '📋',
    title: 'Clear deliverables',
    body: 'Every task should have an output. "Draft v1" beats "work on proposal".',
  ),
  (
    emoji: '🌅',
    title: 'Plan tonight',
    body: 'Spend 5 min tonight planning tomorrow. Wake up with clarity.',
  ),
  (
    emoji: '🛡️',
    title: 'Protect mornings',
    body: 'No meetings before 11am = 2 hours of deep work every day.',
  ),
  (
    emoji: '💆',
    title: 'Rest to recharge',
    body: 'Your brain cycles in 90-min blocks. Take 10 min to recharge.',
  ),
  (
    emoji: '✨',
    title: 'Start small',
    body:
        'If a task feels overwhelming, commit to just 5 minutes. Momentum follows.',
  ),
];

/// Categorize a goal title by keywords. Returns null when no category matches.
String? categorizeGoal(String? title) {
  if (title == null || title.trim().isEmpty) return null;
  final t = title.toLowerCase();
  bool any(List<String> kws) => kws.any(t.contains);

  if (any([
    'run',
    'gym',
    'exercise',
    'workout',
    'fitness',
    'weight',
    'strength',
    'marathon',
    'yoga',
    'health',
    'walk ',
    'cardio',
    'lift',
    'lbs',
    'pound',
    'kg',
  ])) {
    return 'fitness';
  }
  if (any([
    'read',
    'learn',
    'study',
    'course',
    'book',
    'language',
    'skill',
    'tutorial',
    'master',
    'certification',
    'degree',
  ])) {
    return 'learning';
  }
  if (any([
    'save',
    'invest',
    'money',
    'budget',
    'debt',
    'income',
    'wealth',
    'financ',
    'retire',
    'spending',
  ])) {
    return 'finance';
  }
  if (any([
    'career',
    'promot',
    'job',
    'business',
    'startup',
    'launch',
    'salary',
    'work',
    'side hustle',
    'freelance',
    'company',
  ])) {
    return 'career';
  }
  if (any([
    'meditate',
    'mindful',
    'calm',
    'stress',
    'anxiety',
    'sleep',
    'journal',
    'gratitude',
    'present',
  ])) {
    return 'mindfulness';
  }
  if (any([
    'write',
    'paint',
    'draw',
    'music',
    'song',
    'art',
    'creat',
    'design',
    'photo',
    'film',
    'novel',
    'blog',
  ])) {
    return 'creative';
  }
  return null;
}

/// Returns category-specific tips first (so they appear most often), followed
/// by the generic pool. The result is always non-empty.
List<Tip> tipsForGoal(String? goalTitle) {
  final cat = categorizeGoal(goalTitle);
  switch (cat) {
    case 'fitness':
      return [...fitnessTips, ...genericTips];
    case 'learning':
      return [...learningTips, ...genericTips];
    case 'finance':
      return [...financeTips, ...genericTips];
    case 'career':
      return [...careerTips, ...genericTips];
    case 'mindfulness':
      return [...mindfulnessTips, ...genericTips];
    case 'creative':
      return [...creativeTips, ...genericTips];
    default:
      return genericTips;
  }
}
