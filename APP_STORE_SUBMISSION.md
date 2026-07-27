# InputSwitcher App Store Submission

## Product Configuration

- App name: InputSwitcher
- Bundle ID: `com.hans.InputSwitcher`
- Version: `1.1` (`2`)
- Category: Productivity
- Minimum macOS: 13.0
- Business model: Free app with a non-consumable in-app purchase
- In-app purchase product ID: `com.hans.InputSwitcher.pro`
- Reference name: InputSwitcher Pro Lifetime
- US price: $4.99 price point
- Family Sharing: Off unless explicitly enabled in App Store Connect

## Free and Pro Access

Free users can create up to five application rules and use automatic switching, launch at login, default input source, menu display, switch notifications, search, and single-rule deletion.

InputSwitcher Pro is a one-time purchase that unlocks unlimited rules, smart learning, unlimited individual rule locks and global locking, rule import/export, invalid-rule cleanup, and iCloud sync. Free users can lock one rule, and batch editing and deletion are also available for free.

Entitlements are verified with StoreKit 2 `Transaction.currentEntitlements`. Purchase restoration uses `AppStore.sync()` and revoked transactions remove Pro access.

## App Store Connect Setup

1. Create the macOS app with Bundle ID `com.hans.InputSwitcher`.
2. Create a non-consumable product with ID `com.hans.InputSwitcher.pro`.
3. Select the US $4.99 price point and add the localized product names and descriptions from `StoreKit/InputSwitcher.storekit`.
4. Attach the in-app purchase to version 1.1 before submitting it for review.
5. Enable iCloud Key-Value Storage for the App ID and use the same KVS identifier in both signing and App Store Connect.
6. Add a public support URL and host `PRIVACY_POLICY.md` at a public HTTPS URL.
7. Complete the App Privacy questionnaire with “Data Not Collected,” subject to final verification.

## Review Notes

InputSwitcher is a menu bar utility. Click its keyboard icon in the macOS menu bar, then choose Settings.

Free-tier test:

1. Open Settings > Rules.
2. Add five applications and assign input sources.
3. Attempt to add a sixth rule; the InputSwitcher Pro purchase window appears.
4. Click a lock, import/export, cleanup, or iCloud Sync; the same purchase window appears.

Purchase test:

1. Purchase `com.hans.InputSwitcher.pro` using an App Store sandbox account.
2. Confirm the Pro window changes to “Pro Unlocked.”
3. Confirm a sixth rule can be added and all Pro controls are enabled.
4. Reinstall or use a second Mac, choose Restore Purchases, and confirm access is restored.

iCloud test:

1. Sign in to iCloud on two Macs with the same Apple ID.
2. Install builds signed with the same Team, Bundle ID, profile, and KVS entitlement.
3. Enable iCloud Sync after Pro entitlement verification.
4. Change a rule on one Mac and confirm it appears on the other.

## Required Before Submission

- Paid Apple Developer Program enrollment approved
- Distribution certificate and App Store provisioning profile
- Xcode app target with StoreKit configuration assigned to the Run scheme
- App Store product created and Ready to Submit
- Public privacy policy URL
- Support URL and support email
- App screenshots for Rules, General, Pro purchase, and switch HUD
- Final sandbox purchase, restore, refund/revocation, and two-Mac iCloud tests
- Archive validation and upload through Xcode Organizer
