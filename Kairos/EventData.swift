import Foundation

struct EventData: Codable {
    let title: String
    let location: String?
    let startDate: String
    let endDate: String?
    let description: String?
    let allDay: Bool?
    
    enum CodingKeys: String, CodingKey {
        case title
        case location
        case startDate = "start_datetime"
        case endDate = "end_datetime"
        case description
        case allDay = "all_day"
    }
    
    func toDateComponents(from dateString: String) -> DateComponents? {
        let dateFormatters: [(DateFormatter, Set<Calendar.Component>)] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                f.timeZone = TimeZone.current
                return (f, [.year, .month, .day, .hour, .minute, .second])
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.timeZone = TimeZone.current
                return (f, [.year, .month, .day, .hour, .minute, .second])
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone.current
                return (f, [.year, .month, .day])
            }()
        ]
        
        for (formatter, components) in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return Calendar.current.dateComponents(components, from: date)
            }
        }
        
        let iso8601Formatters: [(ISO8601DateFormatter, Set<Calendar.Component>)] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                return (f, [.year, .month, .day, .hour, .minute, .second])
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withFullDate, .withTime, .withTimeZone, .withColonSeparatorInTime]
                return (f, [.year, .month, .day, .hour, .minute, .second, .timeZone])
            }()
        ]
        
        for (formatter, components) in iso8601Formatters {
            if let date = formatter.date(from: dateString) {
                return Calendar.current.dateComponents(components, from: date)
            }
        }
        
        return nil
    }
}
