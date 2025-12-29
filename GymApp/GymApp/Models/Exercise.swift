import Foundation

struct Exercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: ExerciseCategory
    var description: String
    var muscleGroups: [String]
    var equipment: String
    
    static let sampleExercises = [
        Exercise(
            name: "Bench Press",
            category: .chest,
            description: "Lie on a flat bench and press a barbell upward",
            muscleGroups: ["Chest", "Triceps", "Shoulders"],
            equipment: "Barbell"
        ),
        Exercise(
            name: "Squat",
            category: .legs,
            description: "Lower your body by bending your knees and hips",
            muscleGroups: ["Quadriceps", "Hamstrings", "Glutes"],
            equipment: "Barbell"
        ),
        Exercise(
            name: "Deadlift",
            category: .back,
            description: "Lift a barbell from the ground to hip level",
            muscleGroups: ["Back", "Hamstrings", "Glutes"],
            equipment: "Barbell"
        ),
        Exercise(
            name: "Overhead Press",
            category: .shoulders,
            description: "Press a barbell overhead from shoulder height",
            muscleGroups: ["Shoulders", "Triceps"],
            equipment: "Barbell"
        ),
        Exercise(
            name: "Barbell Row",
            category: .back,
            description: "Pull a barbell to your chest while bent over",
            muscleGroups: ["Back", "Biceps"],
            equipment: "Barbell"
        ),
        Exercise(
            name: "Pull-ups",
            category: .back,
            description: "Pull yourself up to a bar",
            muscleGroups: ["Back", "Biceps"],
            equipment: "Pull-up Bar"
        ),
        Exercise(
            name: "Dumbbell Curl",
            category: .arms,
            description: "Curl dumbbells toward your shoulders",
            muscleGroups: ["Biceps"],
            equipment: "Dumbbells"
        ),
        Exercise(
            name: "Tricep Dips",
            category: .arms,
            description: "Lower your body using parallel bars",
            muscleGroups: ["Triceps", "Chest"],
            equipment: "Dip Bars"
        ),
        Exercise(
            name: "Leg Press",
            category: .legs,
            description: "Push weight away using your legs on a machine",
            muscleGroups: ["Quadriceps", "Glutes"],
            equipment: "Leg Press Machine"
        ),
        Exercise(
            name: "Plank",
            category: .core,
            description: "Hold your body in a straight line, supported by forearms and toes",
            muscleGroups: ["Core", "Abs"],
            equipment: "None"
        )
    ]
}

enum ExerciseCategory: String, Codable, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case legs = "Legs"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"
    case cardio = "Cardio"
    case fullBody = "Full Body"
    
    var icon: String {
        switch self {
        case .chest: return "figure.arms.open"
        case .back: return "figure.walk"
        case .legs: return "figure.run"
        case .shoulders: return "figure.arms.open"
        case .arms: return "figure.strengthtraining.traditional"
        case .core: return "figure.core.training"
        case .cardio: return "heart.fill"
        case .fullBody: return "figure.mixed.cardio"
        }
    }
}
