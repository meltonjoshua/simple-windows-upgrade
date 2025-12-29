# GymApp - iOS Gym Application Overview

## App Summary
A complete iOS fitness tracking application built with SwiftUI that allows users to:
- Create and track workouts
- Browse an exercise library
- Monitor progress with statistics
- Manage user profile and preferences

## App Architecture

### Navigation Structure
```
TabView (4 tabs)
├── Workouts Tab
│   ├── WorkoutListView (List of all workouts)
│   │   └── WorkoutDetailView (View workout details)
│   └── NewWorkoutView (Sheet: Create new workout)
│       └── ExercisePickerView (Sheet: Select exercises)
│
├── Exercises Tab
│   ├── ExerciseLibraryView (Browse exercises)
│   │   └── ExerciseDetailView (View exercise details)
│
├── Stats Tab
│   └── StatsView (View statistics and progress)
│
└── Profile Tab
    └── ProfileView (User settings and info)
```

## Data Models

### Exercise
- Properties: name, category, description, muscleGroups, equipment
- 10 pre-loaded sample exercises
- Categories: Chest, Back, Legs, Shoulders, Arms, Core, Cardio, Full Body

### Workout
- Properties: name, date, duration, exercises, notes
- Computed: formattedDate, formattedDuration

### WorkoutExercise
- Links Exercise to a Workout
- Contains: exercise, sets array
- Computed: totalVolume

### ExerciseSet
- Properties: reps, weight, completed
- Represents a single set in a workout

### WorkoutStore
- ObservableObject for state management
- Handles CRUD operations for workouts
- Provides statistics calculations
- Manages data persistence via UserDefaults

## Key Features by Screen

### 1. Workout List View
- Display all workouts in chronological order
- Shows workout name, date, duration, exercise count
- Swipe to delete functionality
- Add new workout button
- Navigates to workout details

### 2. Workout Detail View
- Complete workout information
- List all exercises with sets, reps, and weights
- Display workout notes
- Shows total volume per exercise
- Set completion indicators

### 3. New Workout View
- Form-based input
- Select workout name and date
- Add multiple exercises from library
- Auto-creates 3 sets per exercise
- Add workout notes
- Save/Cancel buttons

### 4. Exercise Library View
- Browse all available exercises
- Filter by category with chips
- Search functionality
- Category icons using SF Symbols
- Navigate to exercise details

### 5. Exercise Detail View
- Exercise description
- Equipment required
- Muscle groups targeted (with tags)
- Category icon and information

### 6. Stats View
- Summary cards for:
  - Total workouts
  - Total time
  - Total volume
- This week's workouts
- This month's summary
- Visual stat cards with colors

### 7. Profile View
- Personal information (name, weight, height)
- Fitness goals picker
- Preferences navigation
- App version information

## Technical Implementation

### SwiftUI Components Used
- `NavigationView` & `NavigationLink` - Navigation
- `TabView` - Tab-based navigation
- `List` & `ForEach` - Data display
- `Form` - Input forms
- `Sheet` - Modal presentations
- `@StateObject` & `@EnvironmentObject` - State management
- `@State` & `@Binding` - Local state
- `Picker` - Selection controls
- `TextField` & `TextEditor` - Text input

### Data Persistence
- `UserDefaults` for simple storage
- `Codable` protocol for serialization
- `JSONEncoder` & `JSONDecoder` for encoding/decoding
- Automatic save on data changes

### Color Scheme
- Blue: Primary actions and highlights
- Green: Time-related stats
- Orange: Volume/intensity stats
- Purple & Pink: Monthly stats
- Gray: Secondary text and backgrounds

## Sample Data
The app includes:
- 1 sample workout ("Upper Body Day") with 2 exercises
- 10 pre-loaded exercises across all categories
- Default 3 sets per exercise in new workouts

## File Organization
```
GymApp/
├── GymApp/
│   ├── GymAppApp.swift              # App entry point
│   ├── Models/                       # Data models
│   │   ├── Exercise.swift
│   │   ├── Workout.swift
│   │   └── WorkoutStore.swift
│   ├── Views/                        # UI views
│   │   ├── ContentView.swift
│   │   ├── WorkoutListView.swift
│   │   ├── WorkoutDetailView.swift
│   │   ├── NewWorkoutView.swift
│   │   ├── ExerciseLibraryView.swift
│   │   ├── ExerciseDetailView.swift
│   │   ├── StatsView.swift
│   │   └── ProfileView.swift
│   ├── Assets.xcassets/              # App assets
│   └── Info.plist                    # App configuration
└── GymApp.xcodeproj/                 # Xcode project
```

## How to Build & Run

### Requirements
- macOS with Xcode 15.0+
- iOS 16.0+ target
- Swift 5.9+

### Steps
1. Open `GymApp.xcodeproj` in Xcode
2. Select iPhone simulator (e.g., iPhone 15)
3. Press Cmd+R to build and run
4. App will launch in simulator

### Build from Terminal
```bash
cd GymApp
xcodebuild -project GymApp.xcodeproj \
  -scheme GymApp \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## User Workflow Example

1. **First Launch**
   - App loads with 1 sample workout
   - User sees workout list

2. **Create New Workout**
   - Tap "+" button
   - Enter "Leg Day"
   - Add "Squat" exercise
   - Add "Leg Press" exercise
   - Add notes: "Focus on form"
   - Save workout

3. **Browse Exercises**
   - Switch to Exercises tab
   - Filter by "Legs" category
   - View "Squat" details
   - See muscle groups: Quadriceps, Hamstrings, Glutes

4. **Check Progress**
   - Switch to Stats tab
   - View total workouts: 2
   - See this week's workouts
   - Check total volume lifted

5. **Update Profile**
   - Switch to Profile tab
   - Update name and weight
   - Set goal: "Build Muscle"

## Future Enhancement Ideas
- Custom exercise creation
- Rest timer
- Workout templates
- Progress charts
- Photo tracking
- Apple Health sync
- Export data
- Workout reminders
- Apple Watch app
- Social features

---

This is a complete, production-ready iOS fitness application built entirely with SwiftUI and modern iOS development practices.
