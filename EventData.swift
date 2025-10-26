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
        case startDate = "start_date"
        case endDate = "end_date"
        case description
        case allDay = "all_day"
    }
    
    func toDateComponents(from dateString: String) -> DateComponents? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone, .withColonSeparatorInTime]
        
        if let date = formatter.date(from: dateString) {
            return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: date)
        }
        
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return Calendar.current.dateComponents([.year, .month, .day], from: date)
        }
        
        return nil
    }
}
