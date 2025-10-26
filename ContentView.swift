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
    @State private var eventData: EventData?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var showingEventPreview = false
    
    private let eventPrompt = """
    Extract event information from this image and return ONLY a list of JSON object with the following structure:
    [{
        "title": "Event title",
        "location": "Event location (optional)",
        "start_date": "YYYY-MM-DDTHH:MM:SS (ISO 8601 format)",
        "end_date": "YYYY-MM-DDTHH:MM:SS (ISO 8601 format, optional)",
        "description": "Event description (optional)",
        "all_day": false
    }]
    
    Important:
    - Return ONLY valid JSON, no additional text
    - Use ISO 8601 format for dates (YYYY-MM-DDTHH:MM:SS)
    - If the date doesn't specify a time, set all_day to true
    - If end_date is not specified, leave it null
    - Extract all visible event details from the image
    - Keep the description short
    """
    
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
                        
                        if let eventData {
                            eventPreviewSection(eventData)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Event Parser")
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
                eventData = nil
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
        eventData = nil
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
        
        if let jsonStartIndex = output.firstIndex(of: "{"),
           let jsonEndIndex = output.lastIndex(of: "}") {
            let jsonString = String(output[jsonStartIndex...jsonEndIndex])
            
            if let jsonData = jsonString.data(using: .utf8) {
                do {
                    let decoder = JSONDecoder()
                    let event = try decoder.decode(EventData.self, from: jsonData)
                    eventData = event
                    model.extractedEventData = event
                } catch {
                    errorMessage = "Failed to parse event data: \(error.localizedDescription)"
                    showingError = true
                }
            }
        } else {
            errorMessage = "No valid JSON found in the response. Please try again with a clearer image."
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
