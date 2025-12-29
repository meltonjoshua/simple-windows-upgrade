import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(workout.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Label(workout.formattedDuration, systemImage: "clock")
                        Spacer()
                        Label("\(workout.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Exercises
                ForEach(workout.exercises) { workoutExercise in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workoutExercise.exercise.name)
                            .font(.headline)
                        
                        ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                
                                Text("\(set.reps) reps")
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(set.volumeString)
                                    .frame(width: 80, alignment: .leading)
                                
                                Spacer()
                                
                                if set.completed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Text("Volume: \(String(format: "%.0f lbs", workoutExercise.totalVolume))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                
                // Notes
                if !workout.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        
                        Text(workout.notes)
                            .font(.body)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle("Workout Details")
    }
}

struct WorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let store = WorkoutStore()
        let sampleWorkout = store.workouts.first ?? Workout(
            name: "Sample Workout",
            date: Date(),
            duration: 3600,
            exercises: [],
            notes: ""
        )
        
        NavigationView {
            WorkoutDetailView(workout: sampleWorkout)
        }
    }
}
