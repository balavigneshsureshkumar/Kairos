import Foundation
import EventKit

class ICSGenerator {
    static func generateICS(from eventData: EventData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYYMMDD'T'HHMMSS"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        
        let now = Date()
        let dtstamp = dateFormatter.string(from: now)
        
        var icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Kairos//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        BEGIN:VEVENT
        UID:\(UUID().uuidString)@kairos.app
        DTSTAMP:\(dtstamp)
        SUMMARY:\(eventData.title)
        """
        
        if let location = eventData.location, !location.isEmpty {
            icsContent += "\nLOCATION:\(location)"
        }
        
        if let description = eventData.description, !description.isEmpty {
            icsContent += "\nDESCRIPTION:\(description.replacingOccurrences(of: "\n", with: "\\n"))"
        }
        
        if let isAllDay = eventData.allDay, isAllDay {
            let allDayFormatter = DateFormatter()
            allDayFormatter.dateFormat = "yyyyMMdd"
            
            if let startComponents = eventData.toDateComponents(from: eventData.startDate),
               let startDate = Calendar.current.date(from: startComponents) {
                icsContent += "\nDTSTART;VALUE=DATE:\(allDayFormatter.string(from: startDate))"
                
                if let endDateString = eventData.endDate,
                   let endComponents = eventData.toDateComponents(from: endDateString),
                   let endDate = Calendar.current.date(from: endComponents) {
                    let adjustedEndDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    icsContent += "\nDTEND;VALUE=DATE:\(allDayFormatter.string(from: adjustedEndDate))"
                } else {
                    let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                    icsContent += "\nDTEND;VALUE=DATE:\(allDayFormatter.string(from: nextDay))"
                }
            }
        } else {
            if let startComponents = eventData.toDateComponents(from: eventData.startDate),
               let startDate = Calendar.current.date(from: startComponents) {
                icsContent += "\nDTSTART:\(dateFormatter.string(from: startDate))"
                
                if let endDateString = eventData.endDate,
                   let endComponents = eventData.toDateComponents(from: endDateString),
                   let endDate = Calendar.current.date(from: endComponents) {
                    icsContent += "\nDTEND:\(dateFormatter.string(from: endDate))"
                } else {
                    let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                    icsContent += "\nDTEND:\(dateFormatter.string(from: oneHourLater))"
                }
            }
        }
        
        icsContent += """
        
        END:VEVENT
        END:VCALENDAR
        """
        
        return icsContent
    }
    
    static func saveToCalendar(eventData: EventData, completion: @escaping (Bool, Error?) -> Void) {
        let eventStore = EKEventStore()
        
        eventStore.requestFullAccessToEvents { granted, error in
            guard granted, error == nil else {
                completion(false, error)
                return
            }
            
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
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }
}
