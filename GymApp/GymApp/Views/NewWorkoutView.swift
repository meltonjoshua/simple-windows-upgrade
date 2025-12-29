import SwiftUI

struct NewWorkoutView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    @Environment(\.dismiss) var dismiss
    
    @State private var workoutName = ""
    @State private var workoutExercises: [WorkoutExercise] = []
    @State private var notes = ""
    @State private var startTime = Date()
    @State private var showingExercisePicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Workout Details")) {
                    TextField("Workout Name", text: $workoutName)
                    
                    DatePicker("Date", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("Exercises")) {
                    ForEach(workoutExercises) { workoutExercise in
                        VStack(alignment: .leading) {
                            Text(workoutExercise.exercise.name)
                                .font(.headline)
                            Text("\(workoutExercise.sets.count) sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: { showingExercisePicker = true }) {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveWorkout()
                    }
                    .disabled(workoutName.isEmpty || workoutExercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(onSelect: addExercise)
            }
        }
    }
    
    private func addExercise(_ exercise: Exercise) {
        let sets = [
            ExerciseSet(reps: 10, weight: 0, completed: false),
            ExerciseSet(reps: 10, weight: 0, completed: false),
            ExerciseSet(reps: 10, weight: 0, completed: false)
        ]
        let workoutExercise = WorkoutExercise(exercise: exercise, sets: sets)
        workoutExercises.append(workoutExercise)
    }
    
    private func saveWorkout() {
        let duration: TimeInterval = 3600 // Default 1 hour
        
        let workout = Workout(
            name: workoutName,
            date: startTime,
            duration: duration,
            exercises: workoutExercises,
            notes: notes
        )
        
        workoutStore.addWorkout(workout)
        dismiss()
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutStore: WorkoutStore
    let onSelect: (Exercise) -> Void
    
    var body: some View {
        NavigationView {
            List(workoutStore.exercises) { exercise in
                Button(action: {
                    onSelect(exercise)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: exercise.category.icon)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(exercise.category.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NewWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        NewWorkoutView()
            .environmentObject(WorkoutStore())
    }
}
