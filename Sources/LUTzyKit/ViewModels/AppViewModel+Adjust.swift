import SwiftUI

/// `AppViewModel`'s adjustment bindings — Step 10b.
///
/// Deliberately thin. Every one of these forwards to a pure function on `AdjustmentControl` and then
/// re-renders; none of them knows how the sparse array is shaped. That is what lets the whole
/// contract be tested without a view model, an engine or a GPU — see `AdjustmentControlTests`.
extension AppViewModel {

    /// What a row should display, in **slider space**.
    ///
    /// **Reading never writes**, the same property `developBinding(for:)` has: an absent node reads
    /// as the control's neutral rather than being seeded into the document. Seeding on open would
    /// make every document non-neutral the moment the panel was looked at, which would in turn make
    /// the A/B comparison offer itself on an untouched image.
    func adjustmentValue(for control: AdjustmentControl) -> Double {
        control.sliderMapped(control.value(in: document.adjustments))
    }

    /// A two-way binding for one row. Slider space on both sides — `sliderMapped` is self-inverse,
    /// so the same call converts each way.
    ///
    /// **Debounced**, because every row here is a continuous control: there are no toggles in this
    /// panel, unlike Develop's three.
    func adjustmentBinding(for control: AdjustmentControl) -> Binding<Double> {
        Binding(
            get: { self.adjustmentValue(for: control) },
            set: { newValue in
                self.updateDocument(debounced: true) { document in
                    document.adjustments = control.setting(
                        control.sliderMapped(newValue), in: document.adjustments
                    )
                }
            }
        )
    }

    /// Return one row to its neutral. Undebounced — `updateDocument(debounced:)`'s contract is that
    /// discrete controls fire immediately.
    func resetAdjustment(_ control: AdjustmentControl) {
        updateDocument { document in
            document.adjustments = control.setting(control.neutral, in: document.adjustments)
        }
    }

    /// Return every row to its neutral.
    ///
    /// Clears `adjustments` and nothing else: `rawDevelop` and the LUT belong to other panels, and a
    /// Reset button that reached across panel boundaries would be a trap.
    func resetAllAdjustments() {
        updateDocument { $0.adjustments = [] }
    }

    /// Whether any row is off its neutral — the Reset button's enabled state.
    ///
    /// Reads the array's emptiness rather than comparing nine values, which is only correct because
    /// the array is sparse: an identity node never survives a write. `AdjustmentControlTests`
    /// pins that.
    var hasAdjustments: Bool { !document.adjustments.isEmpty }
}
