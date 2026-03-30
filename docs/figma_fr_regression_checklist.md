# Figma FR Regression Checklist

Use this checklist after pulling the latest changes and running the app on an Android device.

## Professional Support and Chat

- [ ] Active subscription shows unlocked state and allows starting therapist chat.
- [ ] Cancel at period end shows cancellation-requested state.
- [ ] Canceled/inactive subscription shows read-only history state.
- [ ] Parent can open old conversation in read-only mode when inactive.
- [ ] Parent cannot send messages in read-only mode.
- [ ] Therapist details opens from therapist cards.
- [ ] Therapist details opens from chat header info action.
- [ ] Parent can request emergency support in chat.
- [ ] Therapist sees emergency requested status and can mark responded.
- [ ] Emergency responded state appears in parent and therapist chat UIs.
- [ ] Message sending shows explicit sending/sent/error states.

## Parent and Settings Parity

- [ ] Settings route keys `feedback`, `parent_terms`, `therapist_terms`, and `terms` open mapped screens.
- [ ] Unknown settings route keys still fall back to placeholder screen safely.

## Learning and Game Flows

- [ ] Trace game rejects random scribbles and only accepts valid trace-like paths.
- [ ] `hold_it` modules require long press to answer.
- [ ] `find_it`, `match_it`, `words`, and `sentences` modules show mode-specific prompts.
- [ ] Completion still writes activity progress to Firestore for all updated game modes.

