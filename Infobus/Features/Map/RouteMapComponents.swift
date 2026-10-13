//
//  RouteMapComponents.swift
//  Infobus
//
//  Station and bus pin views shared by the single-route screen and the
//  multi-route "Карта" tab.
//
//  Station pins are now a fixed black-border/white-fill dot regardless of
//  route color — a station is often served by several differently-colored
//  routes at once, so tinting its pin to just one of them was always a
//  little arbitrary, and it fought visually with the also-colored bus
//  markers. Callers scale the whole pin up at close zoom (see
//  `stationScale` in MapView/RouteDetailView) rather than this view
//  knowing about camera distance itself.
//
//  Bus markers stay route-colored (that part wasn't asked to change), but
//  their silhouette is now a "drop" that points in the bus's own heading
//  when one is known — the same idea the old Objective-C app's own bus
//  markers used (see TeardropShape below), rebuilt as a SwiftUI Shape
//  instead of hand-rolled Core Graphics — plus a bigger base size, both
//  per direct feedback that the old plain colored circle was hard to spot
//  at a glance. No glyph drawn inside it either, matching the old app's
//  actual design (color + a small occupancy dot, nothing else) — an
//  earlier pass added a bus.fill icon on top that was never asked for and
//  read as new/unwanted clutter, so it's gone again.
//

import SwiftUI

struct StationPinView: View {
    let isCurrent: Bool

    private let baseDiameter: CGFloat = 12
    private let currentDiameter: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(Color.black, lineWidth: 2)
            // The nearest-to-rider station (only meaningful on the
            // single-route screen) still needs to read as different from
            // every other stop despite the uniform black/white styling —
            // a small accent dot does that without reintroducing a
            // route-color fill.
            if isCurrent {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(
            width: isCurrent ? currentDiameter : baseDiameter,
            height: isCurrent ? currentDiameter : baseDiameter
        )
        .shadow(radius: 1)
    }
}

/// A station pin plus its own tap-to-show-predictions sheet — self-contained
/// so each pin owns its own presentation state instead of one shared sheet
/// driven by a single `@State` at the map's top level. A modal sheet (not a
/// popup) because a busy stop's predictions can run to several routes'
/// worth of arrival times — see StationPredictionSheet's header.
struct StationAnnotationView: View {
    let station: Station
    let isCurrent: Bool
    let fetch: () async -> [StationPredictionRow]
    /// Forwarded straight through to StationPredictionSheet — see its own
    /// header for what this does.
    var colorForRoute: (Int) -> Color? = { _ in nil }
    @State private var isSheetPresented = false

    var body: some View {
        StationPinView(isCurrent: isCurrent)
            .onTapGesture { isSheetPresented = true }
            .sheet(isPresented: $isSheetPresented) {
                StationPredictionSheet(station: station, fetch: fetch, colorForRoute: colorForRoute)
            }
    }
}

struct BusPinView: View {
    let isOffRoute: Bool
    /// nil when Bus.direction was missing on the wire — the pin falls back
    /// to a plain circle in that case, since a drop shape's whole point is
    /// to show which way it's pointed.
    let bearing: Double?
    /// This bus's route color — matches the route's own line color, the
    /// same way the old app colored a route's buses to match its line.
    let routeColor: Color
    /// Cabin occupancy 0–100, nil when not reported. When known, it takes
    /// over the fill color (green/yellow/red) with the route color moving
    /// to a ring around it, so the bus is still identifiable by route even
    /// while showing how full it is.
    let occupancyPercent: Int?

    /// Bumped up well past the original 26pt circle — easier to pick a
    /// bus out at a glance, especially with several routes' worth on
    /// screen together, and a big enough jump to actually read as
    /// noticeably bigger rather than a marginal change.
    private let size: CGFloat = 44

    var body: some View {
        silhouette
            .shadow(radius: 1)
    }

    /// Fill, occupancy ring, and the off-route dashed outline, bundled
    /// into one group so they share a single rotation rather than each
    /// needing `.rotationEffect` repeated on it separately.
    ///
    /// Uses `.stroke` rather than `.strokeBorder` throughout — the latter
    /// needs `InsettableShape`, which the type-erased `AnyShape` used for
    /// `shape` below doesn't conform to (only plain `Shape`). `.stroke`
    /// centers the line on the path instead of insetting it, a pixel or
    /// two of visual difference at this size that isn't worth carrying an
    /// `InsettableShape`-conforming version of `TeardropShape` for.
    private var silhouette: some View {
        ZStack {
            shape.fill(fillColor)
            if occupancyPercent != nil && !isOffRoute {
                shape.stroke(routeColor, lineWidth: 3)
            }
            if isOffRoute {
                shape
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .foregroundStyle(.gray)
                    .padding(-3)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(bearing ?? 0))
    }

    private var shape: AnyShape {
        bearing != nil ? AnyShape(TeardropShape()) : AnyShape(Circle())
    }

    private var fillColor: Color {
        if isOffRoute { return .gray }
        return occupancyColor ?? routeColor
    }

    private var occupancyColor: Color? {
        guard let occupancyPercent else { return nil }
        switch occupancyPercent {
        case ..<40: return .green
        case 40..<75: return .yellow
        default: return .red
        }
    }
}

/// A rounded "drop" pointing up by default — a sharp point at the top,
/// tangent lines down to a round back — matching the silhouette the old
/// (Objective-C) app's own bus markers drew by hand with Core Graphics
/// (`createBusMarkerIconForRouteNumber`), just built as a SwiftUI `Shape`
/// instead. Callers rotate the whole shape with `.rotationEffect` to point
/// it at a bus's actual heading; the shape itself has no idea what
/// direction that is.
private struct TeardropShape: Shape {
    /// Point radius and back-circle radius, both as a fraction of the
    /// shape's own half-size.
    var pointRadius: CGFloat = 1.0
    var backRadius: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(rect.width, rect.height) / 2
        let r1 = pointRadius * scale
        let r2 = backRadius * scale
        guard r1 > 0, r2 > 0, r2 < r1 else {
            return Circle().path(in: rect)
        }

        let tipAngle = -CGFloat.pi / 2 // "up" in this shape's own local space
        let halfSpread = acos(r2 / r1)
        let tangentAngle = tipAngle + halfSpread

        func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        var path = Path()
        path.move(to: point(angle: tipAngle, radius: r1))
        path.addLine(to: point(angle: tangentAngle, radius: r2))

        // The back is the LONG way around the r2 circle (through the
        // bottom, opposite the tip) — built as a short polyline rather
        // than Path's own addArc, which has a well-known clockwise/
        // counterclockwise ambiguity under SwiftUI's flipped (y-down)
        // coordinate space. A plain loop of line segments sidesteps that
        // question entirely instead of guessing at it.
        let sweep = (2 * CGFloat.pi) - (2 * halfSpread)
        let steps = 24
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: point(angle: tangentAngle + sweep * t, radius: r2))
        }

        path.closeSubpath()
        return path
    }
}

/// A bus pin plus its own tap-to-show-info popup — a small anchored bubble
/// (not a bottom sheet, see BusInfoSheet's header), self-contained the same
/// way StationAnnotationView is so the popup anchors to THIS bus specifically.
struct BusAnnotationView: View {
    let bus: Bus
    let isOffRoute: Bool
    let bearing: Double?
    let routeColor: Color
    let occupancyPercent: Int?
    @State private var isPopoverPresented = false

    var body: some View {
        BusPinView(isOffRoute: isOffRoute, bearing: bearing, routeColor: routeColor, occupancyPercent: occupancyPercent)
            .onTapGesture { isPopoverPresented = true }
            .popover(isPresented: $isPopoverPresented) {
                BusInfoSheet(bus: bus)
                    .presentationCompactAdaptation(.popover)
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            StationPinView(isCurrent: false)
            StationPinView(isCurrent: true)
        }
        HStack(spacing: 16) {
            BusPinView(isOffRoute: false, bearing: 45, routeColor: .red, occupancyPercent: nil)
            BusPinView(isOffRoute: false, bearing: 120, routeColor: .red, occupancyPercent: 25)
            BusPinView(isOffRoute: false, bearing: 200, routeColor: .blue, occupancyPercent: 90)
            BusPinView(isOffRoute: true, bearing: nil, routeColor: .green, occupancyPercent: nil)
        }
    }
    .padding()
}
