//
//  RouteMapComponents.swift
//  Infobus
//
//  Station and bus pin views shared by the single-route screen and the
//  multi-route "Карта" tab.
//
//  Station pins are a fixed black-border/white-fill dot regardless of
//  route color — a station is often served by several differently-colored
//  routes at once, so tinting its pin to just one of them was always a
//  little arbitrary, and it fought visually with the also-colored bus
//  markers. Callers scale the whole pin up at close zoom (see
//  `stationScale` in MapView/RouteDetailView) rather than this view
//  knowing about camera distance itself.
//
//  Bus markers follow the written spec's "Вариант №3 — Стрелка
//  направления": a plain circle in the route's color with a white bus
//  glyph centered inside it, a triangular pointer just outside the circle
//  that rotates to the bus's heading, and a colored arc around the
//  outside of the circle whose length and color encode occupancy. The
//  three signals are deliberately independent of one another — route
//  color never changes for occupancy, the pointer never changes shape or
//  color for occupancy, and the arc never touches the circle's own fill —
//  so each can be read (or be absent) without disturbing the others.
//
//  The pointer additionally corrects for the MAP's own current heading,
//  not just the bus's: MapKit's annotation views stay screen-upright on
//  their own (they don't inherit the map's rotation), so a bus's pointer
//  would show its true geographic bearing rather than its bearing
//  *relative to the screen* the moment the user rotates the map (the
//  compass control, or a two-finger twist). Callers pass the live
//  `MapCamera.heading` in for this; it defaults to 0 (north-up) for
//  anything that doesn't track the camera (e.g. the preview below).
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
            .contentShape(Rectangle())
            // `.highPriorityGesture` rather than a plain `.onTapGesture`
            // — same reasoning as the zoom/locate-me buttons in
            // MapView.swift: this pin sits directly inside the `Map`'s
            // own content, which means it's even more exposed than
            // those buttons were to losing a tap to MapKit's own native
            // pan/pinch/double-tap recognizers on the same surface. This
            // makes the pin's own tap win outright instead of competing
            // for the touch.
            .highPriorityGesture(
                TapGesture().onEnded {
                    isSheetPresented = true
                }
            )
            .sheet(isPresented: $isSheetPresented) {
                StationPredictionSheet(station: station, fetch: fetch, colorForRoute: colorForRoute)
            }
    }
}

struct BusPinView: View {
    let isOffRoute: Bool
    /// nil when Bus.direction was missing on the wire — the direction
    /// pointer (and the heading-rotation it needs) only ever appears once
    /// this is known.
    let bearing: Double?
    /// This bus's route color — matches the route's own line color, the
    /// same way the old app colored a route's buses to match its line.
    /// Always the circle's fill AND the pointer's color; occupancy never
    /// touches either.
    let routeColor: Color
    /// Cabin occupancy 0–100, nil when not reported. Drawn as a colored
    /// arc around the OUTSIDE of the circle, its length proportional to
    /// the percentage and its color stepped across four bands — never a
    /// fill/border/dot change on the circle itself, so route identity and
    /// occupancy never compete for the same patch of color.
    let occupancyPercent: Int?
    /// The map camera's current heading (compass degrees the screen's top
    /// currently points to; 0 = north-up) — see the file header for why
    /// the pointer needs this on top of the bus's own bearing.
    var mapHeading: Double = 0

    private let circleDiameter: CGFloat = 34
    private let outlineWidth: CGFloat = 1.75
    /// A bit further out from the circle than before, and the arc itself
    /// is now outlined in black (see `pointerLayer`'s sibling below) so it
    /// reads as its own separate, framed badge rather than something
    /// stuck right onto the circle's edge.
    private let arcDiameter: CGFloat = 46
    private let arcWidth: CGFloat = 3.5
    private let arcFrameWidth: CGFloat = 1.5
    /// The pointer's colored (inner) size — back to what it was before
    /// going smaller to make room for an inward border, per direct
    /// feedback that made the arrow read as less noticeable. The white
    /// border below now grows OUTWARD from this instead, and thicker than
    /// it was originally.
    private let pointerSize = CGSize(width: 16, height: 18)
    private let pointerBorderWidth: CGFloat = 3
    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            if let occupancyColor, !isOffRoute {
                ZStack {
                    // A black backing arc, same path, a bit wider — drawn
                    // first so a thin black edge shows on both sides and
                    // both ends of the colored arc on top of it, framing
                    // it instead of leaving it as a bare colored line.
                    OccupancyArc(fraction: occupancyFraction)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: arcWidth + arcFrameWidth * 2, lineCap: .butt))
                    OccupancyArc(fraction: occupancyFraction)
                        .stroke(occupancyColor, style: StrokeStyle(lineWidth: arcWidth, lineCap: .butt))
                }
                .frame(width: arcDiameter, height: arcDiameter)
                // Starts diametrically opposite the pointer (the arc's
                // own "top" rotated 180° past `screenBearing`) rather
                // than always at the top, and turns together with the
                // pointer — so the filling always sits on the side of
                // the bus AWAY from the direction it's facing, instead
                // of looking like it's stuck off to one side.
                .rotationEffect(.degrees(screenBearing + 180))
            }

            if bearing != nil {
                pointerLayer
            }

            circleLayer

            // Kept OUTSIDE `circleLayer`'s own ZStack and un-rotated, same
            // reasoning as the pointer being in its own layer: a tilted
            // bus glyph would read as wrong rather than as "pointing
            // somewhere" — only the pointer conveys direction.
            Image(systemName: "bus.fill")
                .font(.system(size: circleDiameter * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }

    private var circleLayer: some View {
        Circle()
            .fill(isOffRoute ? Color.gray : routeColor)
            .overlay(
                Circle().stroke(Color.white, lineWidth: outlineWidth)
            )
            .overlay {
                if isOffRoute {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .foregroundStyle(.gray)
                        .padding(-3)
                }
            }
            .frame(width: circleDiameter, height: circleDiameter)
    }

    /// The triangular direction pointer, drawn inside its own `size`×`size`
    /// frame so rotating it pivots around the circle's own center rather
    /// than the triangle's own (off-center) bounding box — authored
    /// tip-up and offset just outside the circle's top edge at rest, then
    /// rotated by `screenBearing`, so a bearing of 0°/90°/180°/270°
    /// (relative to the screen) ends up pointing up/right/down/left —
    /// standard clockwise-from-north compass convention.
    /// The pointer's full visible size, border included — needed to
    /// position it correctly against the circle (see `pointerLayer`)
    /// since the white border now grows OUTWARD past `pointerSize`.
    private var pointerOuterSize: CGSize {
        CGSize(
            width: pointerSize.width + pointerBorderWidth * 2,
            height: pointerSize.height + pointerBorderWidth * 2
        )
    }

    private var pointerLayer: some View {
        ZStack {
            // A bigger white silhouette behind the colored triangle —
            // `Triangle` doesn't conform to `InsettableShape` (same
            // reason the circle's own border is a real `.stroke` rather
            // than a `.strokeBorder`), so a thicker border here is a
            // second, bigger copy underneath rather than an inset
            // stroke. Keeps the colored arrow itself at full size (it
            // was reading as less noticeable when the border ate into it
            // instead) while still standing out against the map.
            Triangle()
                .fill(Color.white)
                .frame(width: pointerOuterSize.width, height: pointerOuterSize.height)
            Triangle()
                // Same color as the body circle ("капля") — route color,
                // or gray while off-route.
                .fill(isOffRoute ? Color.gray : routeColor)
                .frame(width: pointerSize.width, height: pointerSize.height)
        }
        .offset(y: -(circleDiameter / 2 + 1 + pointerOuterSize.height / 2))
        .frame(width: size, height: size)
        .rotationEffect(.degrees(screenBearing))
    }

    /// The bus's geographic bearing, corrected for the map's own current
    /// on-screen rotation — see the file header.
    private var screenBearing: Double {
        (bearing ?? 0) - mapHeading
    }

    private var occupancyFraction: Double {
        guard let occupancyPercent else { return 0 }
        return min(max(Double(occupancyPercent) / 100, 0), 1)
    }

    /// Thresholds and exact colors per spec: 0–30% green, 31–70% yellow,
    /// 71–90% orange, 91–100% red.
    private var occupancyColor: Color? {
        guard let occupancyPercent else { return nil }
        switch occupancyPercent {
        case 0...30: return Color(hex: 0x22C55E)
        case 31...70: return Color(hex: 0xFACC15)
        case 71...90: return Color(hex: 0xF97316)
        default: return Color(hex: 0xEF4444)
        }
    }
}

/// A triangle pointing straight up within its own frame — the direction
/// pointer's base shape before `BusPinView` offsets and rotates it.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A partial ring, `fraction` (0...1) of the way around clockwise starting
/// from the top — the occupancy indicator around a bus pin's circle.
/// Built as a short manual polyline rather than `Path.addArc`, which has a
/// well-known clockwise/counterclockwise ambiguity under SwiftUI's
/// flipped (y-down) coordinate space — the same reasoning the old
/// teardrop marker's back-arc used to use for the same reason.
private struct OccupancyArc: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = -CGFloat.pi / 2 // top
        let sweep = 2 * CGFloat.pi * CGFloat(min(max(fraction, 0), 1))
        let steps = max(2, Int(48 * fraction))
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = startAngle + sweep * t
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private extension Color {
    /// 24-bit RGB, e.g. `Color(hex: 0x22C55E)` — the occupancy-arc colors
    /// are specified as exact hex values rather than a built-in semantic
    /// color (`.green`/`.yellow`/...) that could render slightly
    /// differently from one iOS version to the next.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
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
    var mapHeading: Double = 0
    @State private var isPopoverPresented = false

    var body: some View {
        BusPinView(
            isOffRoute: isOffRoute,
            bearing: bearing,
            routeColor: routeColor,
            occupancyPercent: occupancyPercent,
            mapHeading: mapHeading
        )
        .contentShape(Rectangle())
        // `.highPriorityGesture` rather than a plain `.onTapGesture` —
        // see the identical change on StationAnnotationView for why.
        .highPriorityGesture(
            TapGesture().onEnded {
                isPopoverPresented = true
            }
        )
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
            BusPinView(isOffRoute: false, bearing: 0, routeColor: .red, occupancyPercent: nil)
            BusPinView(isOffRoute: false, bearing: 90, routeColor: .red, occupancyPercent: 20)
            BusPinView(isOffRoute: false, bearing: 180, routeColor: .blue, occupancyPercent: 55)
            BusPinView(isOffRoute: false, bearing: 270, routeColor: .purple, occupancyPercent: 80)
            BusPinView(isOffRoute: false, bearing: 45, routeColor: .orange, occupancyPercent: 95)
            BusPinView(isOffRoute: true, bearing: nil, routeColor: .green, occupancyPercent: nil)
        }
    }
    .padding()
}
