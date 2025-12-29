import Foundation

struct Workout: Identifiable, Codable {
    var id = UUID()
    var name: String
    var date: Date
    var duration: TimeInterval
    var exercises: [WorkoutExercise]
    var notes: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

struct WorkoutExercise: Identifiable, Codable {
    var id = UUID()
    var exercise: Exercise
    var sets: [ExerciseSet]
    
    var totalVolume: Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
}

struct ExerciseSet: Identifiable, Codable {
    var id = UUID()
    var reps: Int
    var weight: Double
    var completed: Bool
    
    var volumeString: String {
        String(format: "%.0f lbs", weight)
    }
}
