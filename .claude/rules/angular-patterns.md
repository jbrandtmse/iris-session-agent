# Angular Patterns

**Technology Scope: Angular / TypeScript only.** These rules apply to work on
the Angular frontend (`ui/src/`). They do not apply to ObjectScript backend
work in `src/IRISCouch/`.

## Subscription-Leak Prevention (Story 11.0 AC #6)

Subscription leaks appeared in three Epic 10 stories (10.3 AppShell, 10.5
Document List, 10.6 Document Detail). Each manifested as the same pattern:
a component kicks off a new HTTP request before the prior one resolved, both
callbacks fire in an unpredictable order, and state bounces (loading flag
flips off then on, error briefly appears then vanishes, stale data overwrites
fresh data). Codifying the prevention pattern here so new code does not
re-introduce these bugs.

### Required pattern for overlapping HTTP requests

Any component that issues HTTP requests in response to user action (filter
changes, pagination, re-fetch, retry, etc.) **must**:

1. **Track the active request.** Store the current Subscription on the
   component:

   ```ts
   private activeRequest?: Subscription;
   ```

2. **Unsubscribe before issuing a new one.** Before every `.subscribe(...)`
   call on a new HTTP request, call `activeRequest?.unsubscribe()` first,
   then reassign. This cancels the in-flight call so its callbacks cannot
   race with the new one.

   ```ts
   load(): void {
     this.activeRequest?.unsubscribe();
     this.loading = true;
     this.activeRequest = this.service.fetch().subscribe({
       next: (data) => { this.data = data; this.loading = false; },
       error: (err) => { this.error = err; this.loading = false; },
     });
   }
   ```

3. **Clean up in `ngOnDestroy`.** Every component that subscribes must
   implement `OnDestroy` and unsubscribe. Prefer the modern idiom:

   ```ts
   private readonly destroyRef = inject(DestroyRef);

   ngOnInit(): void {
     this.service.fetch()
       .pipe(takeUntilDestroyed(this.destroyRef))
       .subscribe(...);
   }
   ```

   …or the classic pattern for codebases that haven't adopted `DestroyRef`:

   ```ts
   private readonly destroy$ = new Subject<void>();

   ngOnInit(): void {
     this.service.fetch()
       .pipe(takeUntil(this.destroy$))
       .subscribe(...);
   }

   ngOnDestroy(): void {
     this.destroy$.next();
     this.destroy$.complete();
     this.activeRequest?.unsubscribe();
   }
   ```

4. **No nested `.subscribe()`.** If a second HTTP call depends on the first,
   compose with `switchMap`, `mergeMap`, or `concatMap`. Nested `.subscribe()`
   calls leak because the outer subscription's cleanup does not cascade to
   the inner one.

   ```ts
   // ❌ leaks — the inner .subscribe is never cleaned up when the outer dies
   this.service.a().subscribe((a) => {
     this.service.b(a.id).subscribe((b) => { this.result = b; });
   });

   // ✅ clean — switchMap cancels any in-flight b() call when a() re-emits
   this.service.a()
     .pipe(switchMap((a) => this.service.b(a.id)), takeUntilDestroyed(this.destroyRef))
     .subscribe((b) => { this.result = b; });
   ```

### Enforcement

- Code review: reviewers must reject any `.subscribe()` call in a component
  that does not satisfy (3). Service-level subscriptions are usually fine
  because services live for the app lifetime, but still prefer composition
  over subscribing where possible.
- Tests: components that issue overlapping requests should have a spec
  asserting that the stale callback does not mutate state after a new
  request is issued. Use `HttpTestingController` to fire the first response
  *after* the second request starts.

### History (where this has bitten us)

- **Story 10.3 (AppShell)**: breadcrumb flashed stale database name while
  navigating quickly between rows. Fixed via `activeRequest` pattern +
  `takeUntil`.
- **Story 10.5 (Document List)**: filter typing-ahead issued overlapping
  `_all_docs` calls; final rendered page wasn't the one the user expected.
- **Story 10.6 (Document Detail)**: conflict-toggle re-fetch raced with the
  initial load, and the _rev shown in the header flipped back to the
  pre-toggle value.

If you find a fourth instance, extend this rule with the new case and cite
the story.

## No Hardcoded Colors in Component CSS (Story 11.0 AC #6)

All color values in Angular component styles **must** reference a CSS custom
property from `ui/src/styles/tokens.css`. Hex colors (`#C33F3F`) and `rgba()`
literals are banned in component CSS.

- Reason: three Epic 10 stories (10.2 Badge, 10.3 ErrorDisplay, 10.4 Button)
  shipped with inline rgba literals that drifted from the design tokens.
- Enforcement: a stylelint rule (`ui/.stylelintrc.json`) runs the
  `color-no-hex` and `declaration-property-value-disallowed-list` checks on
  all files under `ui/src/app/**/*.ts` and `ui/src/app/**/*.css`, with
  `ui/src/styles/tokens.css` as the only allowed location for literal colors.
- If you need a new color or alpha tint, add a token to `tokens.css` with a
  descriptive name (e.g., `--color-danger-bg` rather than
  `--color-red-light`), then reference it from the component.

## Design-Doc ID Encoding (Story 11.0 AC #3)

When building URLs or router paths that include a document ID, use
`encodeDocId()` from `services/document.service.ts` — not `encodeURIComponent()`
directly. `encodeDocId` preserves the literal `/` in `_design/<name>` and
`_local/<name>` composite IDs, which CouchDB's HTTP API expects on the wire.

When navigating to a doc detail route that may contain a design doc ID,
split the ID on `/` and pass the pieces as separate route segments so the
custom `docDetailMatcher` in `app.routes.ts` reassembles them correctly
without Angular percent-encoding the inner `/`:

```ts
const idSegments = row.id.split('/');
this.router.navigate(['/db', dbName, 'doc', ...idSegments]);
```
