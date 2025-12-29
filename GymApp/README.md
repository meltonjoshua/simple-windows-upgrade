# GymApp - Complete iOS Gym & Fitness Tracking Application

A comprehensive iOS application built with SwiftUI for tracking workouts, exercises, and fitness progress.

## Features

### 🏋️ Workout Tracking
- **Create Custom Workouts**: Build personalized workout routines
- **Track Sets & Reps**: Record detailed information for each exercise set
- **Weight Tracking**: Monitor the weight used for each set
- **Workout History**: View all past workouts with complete details
- **Duration Tracking**: Record how long each workout session takes
- **Workout Notes**: Add personal notes to track feelings and observations

### 💪 Exercise Library
- **Comprehensive Exercise Database**: Pre-loaded with 10+ common exercises
- **Exercise Categories**: Organized by muscle groups (Chest, Back, Legs, Shoulders, Arms, Core, Cardio, Full Body)
- **Exercise Details**: View descriptions, muscle groups targeted, and equipment needed
- **Category Filtering**: Quickly find exercises by category
- **Search Functionality**: Search exercises by name
- **Visual Icons**: SF Symbols icons for each exercise category

### 📊 Statistics & Progress
- **Overall Statistics**: 
  - Total number of workouts completed
  - Total time spent working out
  - Total volume (weight × reps) lifted
- **Weekly Progress**: View workouts completed in the last 7 days
- **Monthly Progress**: Track monthly workout frequency and duration
- **Visual Stats Cards**: Clean, easy-to-read statistics display

### 👤 User Profile
- **Personal Information**: Track name, weight, and height
- **Fitness Goals**: Set goals (Build Muscle, Lose Weight, Increase Strength, etc.)
- **Preferences**: Configure app settings
- **App Information**: Version and about information

## Technical Details

### Requirements
- iOS 16.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Architecture
- **Framework**: SwiftUI
- **Architecture Pattern**: MVVM (Model-View-ViewModel)
- **Data Persistence**: UserDefaults with Codable protocol
- **State Management**: Combine framework with @Published properties

### Project Structure
```
GymApp/
├── GymApp/
│   ├── GymAppApp.swift          # Main app entry point
│   ├── Models/
│   │   ├── Exercise.swift        # Exercise model and categories
│   │   ├── Workout.swift         # Workout and exercise set models
│   │   └── WorkoutStore.swift    # Data store and business logic
│   ├── Views/
│   │   ├── ContentView.swift           # Main tab view
│   │   ├── WorkoutListView.swift       # Workout list screen
│   │   ├── WorkoutDetailView.swift     # Workout detail screen
│   │   ├── NewWorkoutView.swift        # Create workout screen
│   │   ├── ExerciseLibraryView.swift   # Exercise library screen
│   │   ├── ExerciseDetailView.swift    # Exercise detail screen
│   │   ├── StatsView.swift             # Statistics screen
│   │   └── ProfileView.swift           # User profile screen
│   ├── Assets.xcassets/         # App icons and assets
│   └── Info.plist               # App configuration
└── GymApp.xcodeproj/            # Xcode project file
```

## Installation & Building

### Using Xcode
1. Clone the repository
2. Open `GymApp.xcodeproj` in Xcode
3. Select your target device (iPhone or iPad simulator)
4. Press `Cmd + R` to build and run

### Building from Command Line
```bash
# Navigate to the GymApp directory
cd GymApp

# Build the project
xcodebuild -project GymApp.xcodeproj -scheme GymApp -configuration Debug

# Or build and run on simulator
xcodebuild -project GymApp.xcodeproj -scheme GymApp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Usage Guide

### Creating a New Workout
1. Tap the **Workouts** tab
2. Tap the **+** button in the top right
3. Enter a workout name
4. Tap **Add Exercise** to select exercises from the library
5. Add sets for each exercise (default: 3 sets)
6. Add optional notes
7. Tap **Save**

### Viewing Exercise Details
1. Tap the **Exercises** tab
2. Browse or search for an exercise
3. Tap on an exercise to view:
   - Description
   - Required equipment
   - Targeted muscle groups

### Tracking Progress
1. Tap the **Stats** tab to view:
   - Total workout count
   - Total time spent exercising
   - Total volume lifted
   - Recent workout history
   - Weekly and monthly summaries

## Key Features Implementation

### Data Models
- **Exercise**: Contains exercise information including name, category, description, muscle groups, and equipment
- **Workout**: Represents a complete workout session with date, duration, exercises, and notes
- **WorkoutExercise**: Links exercises to workouts with set information
- **ExerciseSet**: Individual set data (reps, weight, completion status)

### Data Persistence
- Uses `UserDefaults` for simple, lightweight data storage
- All models conform to `Codable` for easy serialization
- Automatic save on data changes
- Sample workout included for new users

### UI Components
- **Tab-based Navigation**: Easy switching between main features
- **List Views**: Scrollable lists with swipe-to-delete functionality
- **Form-based Input**: Clean forms for data entry
- **Custom Cards**: Visually appealing stat cards and summaries
- **SF Symbols**: Native iOS icons throughout the app

## Pre-loaded Exercises

The app comes with 10 sample exercises:
1. **Bench Press** (Chest)
2. **Squat** (Legs)
3. **Deadlift** (Back)
4. **Overhead Press** (Shoulders)
5. **Barbell Row** (Back)
6. **Pull-ups** (Back)
7. **Dumbbell Curl** (Arms)
8. **Tricep Dips** (Arms)
9. **Leg Press** (Legs)
10. **Plank** (Core)

## Future Enhancements

Potential features for future versions:
- Custom exercise creation
- Rest timer between sets
- Workout templates
- Progress photos
- Charts and graphs
- Export workout data
- Social sharing
- Apple Health integration
- Apple Watch companion app
- Dark mode support
- Workout reminders/notifications

## Development

### Adding New Exercises
To add more exercises to the library, edit `Models/Exercise.swift` and add new entries to the `sampleExercises` array.

### Customizing Themes
The app uses SwiftUI's built-in color system. To customize colors, modify the accent color in `Assets.xcassets/AccentColor.colorset/`.

## License

This project is part of the simple-windows-upgrade repository and is provided as-is for educational purposes.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Support

For questions or issues:
1. Check the app's built-in help
2. Review this README
3. Open an issue on GitHub

---

**Built with ❤️ using SwiftUI**
