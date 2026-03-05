import Foundation
import SwiftData

/// Data access layer for Session persistence.
@MainActor
final class SessionStore {

    /// Save a new session to the model context.
    static func save(_ session: Session, in context: ModelContext) {
        context.insert(session)
        try? context.save()
    }

    /// Fetch all sessions, most recent first.
    static func fetchAll(in context: ModelContext) -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch sessions from the last N days.
    static func fetchRecent(days: Int, in context: ModelContext) -> [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = #Predicate<Session> { $0.date >= cutoff }
        let descriptor = FetchDescriptor<Session>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Delete a session.
    static func delete(_ session: Session, in context: ModelContext) {
        context.delete(session)
        try? context.save()
    }
}
