import { Controller } from "@hotwired/stimulus"

// Live search: submits the form (into the "results" Turbo Frame) once the
// user pauses typing, and straight away when a filter changes.
// Turbo cancels any in-flight frame request when a newer one starts, so slow
// responses can't overwrite newer results.
export default class extends Controller {
  static targets = ["query"]
  static values = { delay: { type: Number, default: 350 } }

  connect() {
    this.lastQuery = this.queryTarget.value
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  queue() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      // Ignore edits that end up back where they started (e.g. typing then deleting a space).
      if (this.queryTarget.value.trim() !== this.lastQuery.trim()) this.submit()
    }, this.delayValue)
  }

  submit() {
    clearTimeout(this.timeout)
    this.lastQuery = this.queryTarget.value
    this.element.requestSubmit()
  }
}
