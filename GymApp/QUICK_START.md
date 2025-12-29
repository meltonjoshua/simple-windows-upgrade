# GymApp Quick Start Guide

## What is GymApp?
GymApp is a complete iOS fitness tracking application that helps you log workouts, track exercises, and monitor your fitness progress.

## Getting Started

### Installation
1. Ensure you have Xcode 15.0 or later installed on your Mac
2. Open `GymApp.xcodeproj` in Xcode
3. Select an iPhone simulator from the device dropdown
4. Press `Cmd + R` to build and run the app

### First Launch
When you first launch the app, you'll see:
- A sample workout called "Upper Body Day" to demonstrate the app's features
- 10 pre-loaded exercises in the Exercise Library
- Empty statistics (will populate as you add workouts)

## Main Features

### 🏋️ Workouts Tab (Bottom Left Icon)
**What you can do:**
- View all your workout history
- Tap any workout to see full details
- Tap the "+" button to create a new workout
- Swipe left on any workout to delete it

**Creating a new workout:**
1. Tap the "+" button in the top right
2. Enter a workout name (e.g., "Leg Day")
3. Select the date and time
4. Tap "Add Exercise" to choose exercises
5. Each exercise automatically gets 3 sets (customize as needed)
6. Add optional notes
7. Tap "Save"

### 💪 Exercises Tab (Second Icon)
**What you can do:**
- Browse the complete exercise library
- Filter exercises by category (Chest, Back, Legs, etc.)
- Search for specific exercises
- View detailed information about each exercise

**Exercise categories:**
- Chest
- Back
- Legs
- Shoulders
- Arms
- Core
- Cardio
- Full Body

**Viewing exercise details:**
1. Tap any exercise
2. See the description, equipment needed, and muscle groups targeted

### 📊 Stats Tab (Third Icon)
**What you can do:**
- View total workouts completed
- See total time spent working out
- Check total volume (weight × reps) lifted
- Review this week's workouts
- Check monthly progress

**Understanding the stats:**
- **Total Workouts**: Number of completed workout sessions
- **Total Time**: Combined duration of all workouts
- **Total Volume**: Sum of (weight × reps) across all exercises
- **This Week**: Workouts from the last 7 days
- **This Month**: Summary of the last 30 days

### 👤 Profile Tab (Right Icon)
**What you can do:**
- Update your name, weight, and height
- Set your fitness goal
- Access app preferences
- View app information

**Available fitness goals:**
- Build Muscle
- Lose Weight
- Increase Strength
- Improve Endurance
- General Fitness

## Pre-loaded Exercises

The app includes these exercises:

**Chest:**
- Bench Press

**Back:**
- Deadlift
- Barbell Row
- Pull-ups

**Legs:**
- Squat
- Leg Press

**Shoulders:**
- Overhead Press

**Arms:**
- Dumbbell Curl
- Tricep Dips

**Core:**
- Plank

## Tips & Tricks

### Workout Tracking
- Create workouts immediately after finishing them while details are fresh
- Use the notes field to record how you felt, energy levels, or adjustments
- Check off sets as you complete them during your workout

### Exercise Library
- Use the category filter chips to quickly find exercises for specific muscle groups
- Tap "All" to clear filters and see all exercises
- Use the search bar for quick exercise lookup

### Statistics
- Check your stats regularly to track progress
- Weekly stats help you maintain consistency
- Monthly stats show long-term trends

### Data Management
- All data is saved automatically
- Workouts persist between app launches
- Swipe to delete unwanted workout entries

## Sample Workflow

Here's a typical user journey:

1. **Morning Planning**
   - Open GymApp
   - Check Stats tab to see this week's progress
   - Decide on today's workout focus

2. **At the Gym**
   - Create a new workout: "Morning Upper Body"
   - Add exercises: Bench Press, Barbell Row, Overhead Press
   - Log sets, reps, and weights as you complete them
   - Add notes: "Felt strong today, increased weight on bench"

3. **After Workout**
   - Review workout details
   - Check updated stats
   - Plan next workout based on muscle groups trained

4. **Weekly Review**
   - Check Stats tab for weekly summary
   - Review total volume to track strength gains
   - Adjust profile goals if needed

## Troubleshooting

### App won't build
- Ensure you're using Xcode 15.0 or later
- Check that iOS deployment target is set to 16.0+
- Clean build folder (Cmd + Shift + K) and rebuild

### Data not saving
- Data saves automatically to UserDefaults
- Don't force quit app during save operations
- If issues persist, restart the app

### Can't find an exercise
- Check if filters are applied (tap "All" to clear)
- Use the search bar to search by name
- Remember: current version has 10 pre-loaded exercises

## Next Steps

Now that you understand the basics:

1. **Create your first workout** from scratch
2. **Explore the exercise library** to plan future workouts
3. **Set your fitness goal** in the Profile tab
4. **Track consistently** for best results

## Need Help?

- Refer to the main README.md for technical details
- Check APP_OVERVIEW.md for architecture information
- Review the source code for customization options

---

**Enjoy tracking your fitness journey with GymApp!** 💪🏋️📊
