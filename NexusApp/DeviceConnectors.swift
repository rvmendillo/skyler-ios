import Foundation
import Contacts
import EventKit
import Photos
import HealthKit
import CoreLocation
import MediaPlayer

@MainActor
final class DeviceConnectorHub: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let contacts = CNContactStore()
    private let events = EKEventStore()
    private let health = HKHealthStore()
    private let location = CLLocationManager()
    private var pendingLocation: (([KnowledgeRecord]) -> Void)?

    override init() {
        super.init()
        location.delegate = self
    }

    func connect(_ id: String, completion: @escaping ([KnowledgeRecord], String) -> Void) {
        switch id {
        case "contacts": Task { completion(await loadContacts(), "Connected") }
        case "calendar": Task { completion(await loadCalendar(), "Connected") }
        case "reminders": Task { completion(await loadReminders(), "Connected") }
        case "photos": Task { completion(await loadPhotos(), "Connected") }
        case "health": Task { completion(await loadHealth(), "Connected") }
        case "music": Task { completion(await loadMusic(), "Connected") }
        case "location":
            pendingLocation = { completion($0, "Connected") }
            location.requestWhenInUseAuthorization()
            location.requestLocation()
        default: completion([], "Use import/OAuth")
        }
    }

    private func loadContacts() async -> [KnowledgeRecord] {
        do { _ = try await contacts.requestAccess(for: .contacts) } catch { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var result: [KnowledgeRecord] = []
        try? contacts.enumerateContacts(with: req) { c, _ in
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            result.append(.init(
                id: "contact-\(c.identifier)",
                source: "Contacts",
                kind: .contact,
                timestamp: nil,
                title: name.isEmpty ? c.organizationName : name,
                text: c.organizationName,
                metadata: [:]
            ))
        }
        return result
    }

    private func loadCalendar() async -> [KnowledgeRecord] {
        do { _ = try await events.requestFullAccessToEvents() } catch { return [] }
        let start = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let end = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        return events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil)).map { e in
            .init(
                id: "event-\(e.eventIdentifier ?? UUID().uuidString)",
                source: "Calendar",
                kind: .event,
                timestamp: e.startDate,
                title: e.title ?? "Event",
                text: e.notes ?? "",
                metadata: ["calendar": e.calendar.title]
            )
        }
    }

    private func loadReminders() async -> [KnowledgeRecord] {
        do { _ = try await events.requestFullAccessToReminders() } catch { return [] }
        return await withCheckedContinuation { cont in
            events.fetchReminders(matching: events.predicateForReminders(in: nil)) { reminders in
                let out = (reminders ?? []).map { r in
                    KnowledgeRecord(
                        id: "reminder-\(r.calendarItemIdentifier)",
                        source: "Reminders",
                        kind: .reminder,
                        timestamp: r.dueDateComponents?.date,
                        title: r.title,
                        text: r.notes ?? "",
                        metadata: ["completed": r.isCompleted.description]
                    )
                }
                cont.resume(returning: out)
            }
        }
    }

    private func loadPhotos() async -> [KnowledgeRecord] {
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else { return [] }
        let fetch = PHAsset.fetchAssets(with: nil)
        var out: [KnowledgeRecord] = []
        let limit = min(fetch.count, 5000)
        for i in 0..<limit {
            let a = fetch.object(at: i)
            out.append(.init(
                id: "photo-\(a.localIdentifier)",
                source: "Photos",
                kind: .media,
                timestamp: a.creationDate,
                title: a.mediaType == .video ? "Video" : "Photo",
                text: "",
                metadata: [
                    "favorite": a.isFavorite.description,
                    "width": "\(a.pixelWidth)",
                    "height": "\(a.pixelHeight)"
                ]
            ))
        }
        return out
    }

    private func loadHealth() async -> [KnowledgeRecord] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        var sampleTypes: [HKSampleType] = []
        var readTypes = Set<HKObjectType>()

        func add(_ type: HKSampleType?) {
            guard let type else { return }
            sampleTypes.append(type)
            readTypes.insert(type)
        }

        add(HKObjectType.quantityType(forIdentifier: .stepCount))
        add(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned))
        add(HKObjectType.quantityType(forIdentifier: .heartRate))
        add(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))

        do {
            try await health.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            return []
        }

        var out: [KnowledgeRecord] = []
        for type in sampleTypes {
            let samples: [HKSample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(
                    sampleType: type,
                    predicate: nil,
                    limit: 1000,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                ) { _, samples, _ in
                    cont.resume(returning: samples ?? [])
                }
                health.execute(q)
            }
            out += samples.map { s in
                .init(
                    id: "health-\(s.uuid.uuidString)",
                    source: "Apple Health",
                    kind: .health,
                    timestamp: s.startDate,
                    title: type.identifier,
                    text: healthValue(s),
                    metadata: [:]
                )
            }
        }
        return out
    }

    private func healthValue(_ s: HKSample) -> String {
        if let q = s as? HKQuantitySample { return q.quantity.description }
        if let c = s as? HKCategorySample { return "value \(c.value)" }
        return "sample"
    }

    private func loadMusic() async -> [KnowledgeRecord] {
        let status = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return [] }
        return (MPMediaQuery.songs().items ?? []).prefix(5000).map { item in
            .init(
                id: "music-\(item.persistentID)",
                source: "Music Library",
                kind: .music,
                timestamp: item.releaseDate,
                title: item.title ?? "Track",
                text: [item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " — "),
                metadata: [:]
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        pendingLocation?([.init(
            id: "location-\(Int(l.timestamp.timeIntervalSince1970))",
            source: "Location",
            kind: .location,
            timestamp: l.timestamp,
            title: "Current location sample",
            text: "\(l.coordinate.latitude), \(l.coordinate.longitude)",
            metadata: ["accuracy": "\(l.horizontalAccuracy)"]
        )])
        pendingLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingLocation?([])
        pendingLocation = nil
    }
}
