import AVFoundation
import MLXLMCommon
import SwiftUI
import PhotosUI
import EventKit

extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

struct ContentView: View {
    @State private var model = FastVLMModel()
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isProcessing = false
    @State private var eventData: [EventData] = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var showingEventPreview = false
    
    private var eventPrompt: String {
        return """
        You are a calendar event extraction system. Your task is to analyze text extracted from images and identify all calendar events, meetings, appointments, deadlines, or time-sensitive activities.

        INSTRUCTIONS:
        - Parse the provided image for ANY event information including meetings, appointments, deadlines, classes, social events, reminders, etc.
        - Return ONLY the raw JSON object - NO markdown formatting, NO code blocks, NO backticks, NO explanations

        OUTPUT REQUIREMENTS:
        - Respond with ONLY the JSON object - no ```json``` formatting
        - If no events found, return []

        JSON SCHEMA:
        [
            {
              "title": "string (required) - descriptive event name",
              "location": "string (optional) - physical or virtual address or location name",
              "notes": "string (optional) - additional details, context, web-searched info like airport details, venue info, contact details, performers"
            }
        ] 
        
        CRITICAL: Return only the raw JSON object without any markdown formatting or code block syntax.
        """
    }
    
    private var eventDatetimePrompt: String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY"
        let todayString = dateFormatter.string(from: currentDate)
        
        return """
        You are a event date time extraction system. Your task is to analyze images and identify the start and end timings.
        
        INSTRUCTIONS:
        - For dates/times: Convert relative references (tomorrow, next week, Monday) to actual dates based on today being \(todayString)
        - Extract ONLY information contained within the image
        - Return ONLY the raw JSON object - NO markdown formatting, NO code blocks, NO backticks, NO explanations
        

        OUTPUT REQUIREMENTS:
        - Respond with ONLY the JSON object - no ```json``` formatting

        JSON SCHEMA:
        {
          "start_date": "string (required, any date associated with the event) - YYYY-MM-DD",
          "start_time": "string (required, any timing associated with the event) - HH:MM",
          "end_date": "string (optional, ignore if not in image) - YYYY-MM-DD",
          "end_time": "string (optional, ignore if not in image) - HH:MM"
        }

        CRITICAL: Return only the raw JSON object without any markdown formatting or code block syntax.
        """
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if model.modelInfo.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading model...")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if model.modelInfo.contains("Error") {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Model Error")
                                .font(.headline)
                            Text(model.modelInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        imageSection
                        
                        if selectedImage != nil {
                            actionButtons
                        }
                        
                        if isProcessing {
                            processingSection
                        }
                        
                        if !model.output.isEmpty {
                            responseSection
                        }
                        
                        if !eventData.isEmpty {
                            eventsPreviewSection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Kairos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            sourceType = .camera
                            showingImagePicker = true
                        }) {
                            Label("Take Photo", systemImage: "camera")
                        }
                        
                        Button(action: {
                            sourceType = .photoLibrary
                            showingImagePicker = true
                        }) {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: sourceType, selectedImage: $selectedImage)
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Event successfully added to your calendar!")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await model.load()
        }
    }
    
    private var imageSection: some View {
        VStack(spacing: 12) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Select an image containing event details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Take a photo or choose from your library")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                selectedImage = nil
                eventData = []
                model.output = ""
                model.extractedEventData = nil
            }) {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(action: {
                processImage()
            }) {
                Label("Extract Event", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
        }
    }
    
    private var processingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            
            Text("Processing image...")
                .font(.headline)
            
            if !model.promptTime.isEmpty {
                Text("TTFT: \(model.promptTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Response")
                .font(.headline)
            
            ScrollView {
                Text(model.output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var eventsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Found \(eventData.count) Event\(eventData.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            ForEach(Array(eventData.enumerated()), id: \.offset) { index, event in
                eventCard(event, index: index)
            }
            
            Button(action: {
                addAllEventsToCalendar()
            }) {
                Label("Add All to Calendar", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private func eventCard(_ event: EventData, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event \(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .top) {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.title)
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
            
            if let location = event.location, !location.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "location")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.body)
                    }
                }
            }
            
            HStack(alignment: .top) {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.startDate)
                        .font(.body)
                }
            }
            
            if let endDate = event.endDate {
                HStack(alignment: .top) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(endDate)
                            .font(.body)
                    }
                }
            }
            
            if let description = event.description, !description.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(description)
                            .font(.body)
                    }
                }
            }
            
            if event.allDay == true {
                HStack {
                    Image(systemName: "sun.max")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("All-day event")
                        .font(.body)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func eventPreviewSection(_ event: EventData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Event Preview")
                    .font(.headline)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(event.title)
                            .font(.body)
                    }
                }
                
                if let location = event.location, !location.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "location")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(location)
                                .font(.body)
                        }
                    }
                }
                
                HStack(alignment: .top) {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(event.startDate)
                            .font(.body)
                    }
                }
                
                if let endDate = event.endDate {
                    HStack(alignment: .top) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("End")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(endDate)
                                .font(.body)
                        }
                    }
                }
                
                if let description = event.description, !description.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "text.alignleft")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(description)
                                .font(.body)
                        }
                    }
                }
                
                if event.allDay == true {
                    HStack {
                        Image(systemName: "sun.max")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("All-day event")
                            .font(.body)
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            
            Button(action: {
                addToCalendar(event)
            }) {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private func processImage() {
        guard let selectedImage else { return }
        
        isProcessing = true
        eventData = []
        model.output = ""
        model.extractedEventData = nil
        
        let ciImage = CIImage(image: selectedImage) ?? CIImage()
        
        let userInput = UserInput(
            prompt: .text(eventPrompt),
            images: [.ciImage(ciImage)]
        )
        
        Task {
            let task = await model.generate(userInput)
            await task.value
            
            await MainActor.run {
                isProcessing = false
                parseEventData()
            }
        }
    }
    
    private func parseEventData() {
        let output = model.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let arrayStartIndex = output.firstIndex(of: "[")
        let objectStartIndex = output.firstIndex(of: "{")
        let arrayEndIndex = output.lastIndex(of: "]")
        let objectEndIndex = output.lastIndex(of: "}")
        
        var jsonString: String?
        var isArray = false
        
        if let arrStart = arrayStartIndex, let arrEnd = arrayEndIndex {
            if let objStart = objectStartIndex {
                if arrStart < objStart {
                    jsonString = String(output[arrStart...arrEnd])
                    isArray = true
                } else {
                    if let objEnd = objectEndIndex {
                        jsonString = String(output[objStart...objEnd])
                        isArray = false
                    }
                }
            } else {
                jsonString = String(output[arrStart...arrEnd])
                isArray = true
            }
        } else if let objStart = objectStartIndex, let objEnd = objectEndIndex {
            jsonString = String(output[objStart...objEnd])
            isArray = false
        }
        
        guard var jsonString = jsonString else {
            errorMessage = "No valid JSON found in the response. Please try again with a clearer image."
            showingError = true
            return
        }
        
        if !isArray {
            jsonString = "[" + jsonString + "]"
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            errorMessage = "Failed to convert response to data."
            showingError = true
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let events = try decoder.decode([EventData].self, from: jsonData)
            if !events.isEmpty {
                eventData = events
                model.extractedEventData = events.first
            } else {
                errorMessage = "No events found in the response."
                showingError = true
            }
        } catch {
            errorMessage = "Failed to parse event data: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func addToCalendar(_ event: EventData) {
        ICSGenerator.saveToCalendar(eventData: event) { success, error in
            DispatchQueue.main.async {
                if success {
                    showingSuccess = true
                } else {
                    errorMessage = error?.localizedDescription ?? "Failed to add event to calendar"
                    showingError = true
                }
            }
        }
    }
    
    private func addAllEventsToCalendar() {
        let eventStore = EKEventStore()
        
        eventStore.requestFullAccessToEvents { granted, error in
            guard granted, error == nil else {
                DispatchQueue.main.async {
                    errorMessage = error?.localizedDescription ?? "Calendar access denied"
                    showingError = true
                }
                return
            }
            
            var successCount = 0
            var failureCount = 0
            
            for eventData in eventData {
                let event = EKEvent(eventStore: eventStore)
                event.title = eventData.title
                event.calendar = eventStore.defaultCalendarForNewEvents
                
                if let location = eventData.location {
                    event.location = location
                }
                
                if let description = eventData.description {
                    event.notes = description
                }
                
                if let isAllDay = eventData.allDay, isAllDay {
                    event.isAllDay = true
                }
                
                if let startComponents = eventData.toDateComponents(from: eventData.startDate),
                   let startDate = Calendar.current.date(from: startComponents) {
                    event.startDate = startDate
                    
                    if let endDateString = eventData.endDate,
                       let endComponents = eventData.toDateComponents(from: endDateString),
                       let endDate = Calendar.current.date(from: endComponents) {
                        event.endDate = endDate
                    } else {
                        let duration: TimeInterval = (eventData.allDay ?? false) ? 86400 : 3600
                        event.endDate = startDate.addingTimeInterval(duration)
                    }
                }
                
                do {
                    try eventStore.save(event, span: .thisEvent)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }
            
            DispatchQueue.main.async {
                if failureCount == 0 {
                    showingSuccess = true
                } else if successCount > 0 {
                    errorMessage = "Added \(successCount) event(s), failed to add \(failureCount) event(s)"
                    showingError = true
                } else {
                    errorMessage = "Failed to add events to calendar"
                    showingError = true
                }
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContentView()
}
