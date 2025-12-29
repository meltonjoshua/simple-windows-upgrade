import Foundation
import Combine

class WorkoutStore: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var exercises: [Exercise] = Exercise.sampleExercises
    
    private let workoutsKey = "saved_workouts"
    
    init() {
        loadWorkouts()
    }
    
    func addWorkout(_ workout: Workout) {
        workouts.insert(workout, at: 0)
        saveWorkouts()
    }
    
    func deleteWorkout(at offsets: IndexSet) {
        workouts.remove(atOffsets: offsets)
        saveWorkouts()
    }
    
    func updateWorkout(_ workout: Workout) {
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
            saveWorkouts()
        }
    }
    
    // Statistics
    var totalWorkouts: Int {
        workouts.count
    }
    
    var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }
    
    var totalVolume: Double {
        workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.totalVolume }
        }
    }
    
    func workoutsThisWeek() -> [Workout] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workouts.filter { $0.date >= weekAgo }
    }
    
    func workoutsThisMonth() -> [Workout] {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return workouts.filter { $0.date >= monthAgo }
    }
    
    // Persistence
    private func saveWorkouts() {
        if let encoded = try? JSONEncoder().encode(workouts) {
            UserDefaults.standard.set(encoded, forKey: workoutsKey)
        }
    }
    
    private func loadWorkouts() {
        if let data = UserDefaults.standard.data(forKey: workoutsKey),
           let decoded = try? JSONDecoder().decode([Workout].self, from: data) {
            workouts = decoded
        } else {
            // Add sample workout for demo
            workouts = [createSampleWorkout()]
        }
    }
    
    private func createSampleWorkout() -> Workout {
        let benchPress = Exercise.sampleExercises[0]
        let squat = Exercise.sampleExercises[1]
        
        return Workout(
            name: "Upper Body Day",
            date: Date().addingTimeInterval(-86400),
            duration: 3600,
            exercises: [
                WorkoutExercise(
                    exercise: benchPress,
                    sets: [
                        ExerciseSet(reps: 10, weight: 135, completed: true),
                        ExerciseSet(reps: 8, weight: 155, completed: true),
                        ExerciseSet(reps: 6, weight: 175, completed: true)
                    ]
                ),
                WorkoutExercise(
                    exercise: squat,
                    sets: [
                        ExerciseSet(reps: 10, weight: 185, completed: true),
                        ExerciseSet(reps: 8, weight: 205, completed: true),
                        ExerciseSet(reps: 6, weight: 225, completed: true)
                    ]
                )
            ],
            notes: "Great session! Felt strong."
        )
    }
}
