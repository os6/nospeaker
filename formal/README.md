# `nospeaker` Formal Methods & Quiescence Verification Suite

This directory contains the self-contained, machine-checked formal specifications, SMT-LIB2 bit-accurate IEEE-754 / BitVector proofs, Z3 multi-theory obligations, and Swift 6 strict-concurrency reference contracts verifying every security, memory-safety, concurrency, POSIX/TTY, FFI, DSP numerical, physical hardware, and supply-chain invariant of `nospeaker`.

---

## 1. Formal Verification Artifacts

| File | Toolchain | Scope & Guarantees |
| :--- | :--- | :--- |
| [`NoSpeakerSpec.lean`](./NoSpeakerSpec.lean) | **Lean 4.36.0** (`lean`) | **15 namespaces, 55+ definitions & theorems, 48 `#print axioms` kernel audits.** Proves dual existential refutations (against unhardened `e02a121`) and universal safety/liveness/complexity invariants across **all 24 findings (`V-01`..`V-09`, `IH-01`..`IH-15`) + Round-1 closure (`H-1`..`H-3`)** with **0 `sorry`, 0 `sorryAx`, 0 custom axioms, and 0 warnings**. |
| [`ieee754_and_bv_proofs.smt2`](./ieee754_and_bv_proofs.smt2) | **Z3 5.3.3** (`QF_FP`, `QF_BV`) | **19/19 bit-accurate IEEE-754 (`Binary64`, `Binary32`, `Binary16`) & 64/32/16-bit BitVector obligations** (`T1A`..`T6B`), covering Smith's scaled complex division, `clamp01` `NaN` elimination, `Int64 -> UInt32` PCM bounds, `MTTouch` stride/alignment safety, POSIX `mode_t` `umask 077` & `S_IFMT == S_IFREG` bitmasks, Schur-guarded Levinson-Durbin reflection (`|k| <= 0.999999`), and `NaN` RMS muting. |
| [`z3_security_performance_suite.py`](./z3_security_performance_suite.py) | **Python 3 + Z3Py** (`QF_FP`, `QF_BV`, `QF_LIA`, `QF_LRA`, `QF_NRA`) | **32/32 paired `[Refutation: sat]` + `[Proof: unsat]` obligations (`T1`..`T16`)**, covering subprocess non-interference, complex division, LRA simplex/thermal RC ODEs, `Float32 -> Int` quantization, renderer join barriers, FD idempotence, `>121x` prefix-sum DSP speedup, real-time deadline schedulability, supply-chain gatekeeping, `mkdtemp`/`lstat` TOCTOU, `EINTR` `writeLoop` conservation, monotonic signal phases, TTY/UTF-8/UI bounds, Darwin/IOKit/CoreAudio/CF/Mach-clock safety, Levinson-Durbin / script gates, and Round-1 closure (`H-1`..`H-3`). |
| [`HardenedSecurityContracts.swift`](./HardenedSecurityContracts.swift) | **Swift 6.0+** (`swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -O`) | Proof-carrying Swift 6 `Sendable` reference contracts (`SanitizedTerminalString`, `HardenedSpeechSynthesizer`, `VerifiedActuation`, `ThermalDutyGovernor`, `SmithComplex`, `FastSpeechDSP`, `HeapUnfairLock`, `RendererLifecycleCoordinator`, `IdempotentFDGuard`, `SafeTouchContact`, `EINTRSafeTerminalWriter`, `MonotonicLifecycleGate`, `DebouncedURLOpener`) typechecking with **0 errors and 0 warnings** on both `arm64-apple-macos12` and `x86_64-apple-macos13`. |
| [`verify_all.sh`](./verify_all.sh) | POSIX `sh` | Deterministic one-command verification harness executing all 4 suites sequentially under `set -eu`. |

---

## 2. Running the Verification Suite

Run the complete four-stage formal verification suite from the repository root:

```sh
./formal/verify_all.sh
```

Or invoke each verifier individually:

```sh
# 1. Lean 4.36.0 kernel proof & axiom audit (expect exit 0, zero warnings, zero sorryAx)
lean formal/NoSpeakerSpec.lean

# 2. Z3 SMT-LIB2 IEEE-754 & BitVector proofs (19 check-sat obligations)
z3 formal/ieee754_and_bv_proofs.smt2

# 3. Z3Py multi-theory refutation + universal proof suite (32/32 PASS)
python3 formal/z3_security_performance_suite.py

# 4. Swift 6 strict-concurrency contract typecheck (0 errors, 0 warnings on arm64 & x86_64)
swiftc -module-cache-path /tmp/swift-module-cache \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macos12 \
    -parse-as-library \
    -typecheck formal/HardenedSecurityContracts.swift

swiftc -module-cache-path /tmp/swift-module-cache \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -O \
    -target x86_64-apple-macos13 \
    -parse-as-library \
    -typecheck formal/HardenedSecurityContracts.swift
```

---

## 3. Formal Quiescence Traceability Matrix (`dstadulis/nospeaker#1`..`#24`)

Every vulnerability from the initial security audit (`V-01`..`V-09`) and the exhaustive static sweep (`IH-01`..`IH-15`) is mapped 1-to-1 across fork issue tracking, hardened implementation commits/symbols (`harden/app`), Lean 4 kernel theorems (`NoSpeakerSpec.lean`), and Z3 SMT obligations:

| Finding | Fork Issue (`dstadulis/nospeaker`) | `harden/app` Commit & Hardened Symbols | Lean 4.36 Theorems (`NoSpeakerSpec.lean`) | Z3 SMT Obligations (`ieee754_and_bv_proofs.smt2` / `z3_security_performance_suite.py`) |
| :--- | :--- | :--- | :--- | :--- |
| **V-01** | [#1](https://github.com/dstadulis/nospeaker/issues/1) (CWE-494/829) | `f52dd6a`, `53b7f64`, `88c41b4` · `play.sh` (`codesign --verify --deep --strict --check-notarization -R=...`, `spctl --assess`, fail-closed `shasum -a 256`, `zipinfo`) | `SupplyChainGatekeeper.unhardened_play_sh_bypasses_gatekeeper`, `play_sh_exec_admissible_iff`, `full_install_admissible_iff`, `umask_077_clears_group_and_world`, `VerifierRound1Closure.h3_sha256_fail_closed_sound` | `T9.Refute`, `T9.Prove`, `T16.Refute`, `T16.Prove` (`z3_security_performance_suite.py`), `T5A`, `T5B` (`ieee754_and_bv_proofs.smt2`) |
| **V-02** | [#2](https://github.com/dstadulis/nospeaker/issues/2) (CWE-88/214) | `94116c5` · `render(_:)`, `sanitizeSpeechText(_:)`, `isValidVoiceToken(_:)` (`-f -` stdin `Pipe`, `[`/`]` DSL strip) | `SubprocessSecurity.unhardened_render_violates_isolation`, `hardened_render_complete_mediation`, `hardened_render_noninterference`, `sanitizeSpeechInput_sound`, `isValidVoiceToken_sound`, `ConcreteRefinement.foldSpeechScalar_sound` | `T1.Refute`, `T1.Prove` (`z3_security_performance_suite.py`) |
| **V-03** | [#3](https://github.com/dstadulis/nospeaker/issues/3) (CWE-190/400) | `94116c5` · `render(_:)`, `analyse(_:sampleRate:)`, `maxAllowedAudioFrames` (`1_440_000`, `UInt32(exactly:)`, `[8000, 96000] Hz`) | `MemoryBounds.unhardened_pcm_frame_overflow_trap`, `bounded_pcm_frames_safe`, `validated_sample_rate_windows` | `T3A`, `T3B` (`ieee754_and_bv_proofs.smt2`) |
| **V-04** | [#4](https://github.com/dstadulis/nospeaker/issues/4) (CWE-125/704) | `7311fa7` · `MultitouchAPI`, `onTouchFrame` (`idx < min(count, 4)`, `loadUnaligned`), `touchToPlay()`, `safeIndex(_:count:)` | `MemoryBounds.mttouch_unhardened_stride_hazards`, `validated_stride_in_bounds`, `quantized_scale_index_in_bounds`, `ConcreteRefinement.mttouch_min4_cap_prevents_88b_oob` | `T4A.1`, `T4A.2`, `T4B` (`ieee754_and_bv_proofs.smt2`), `T5.Refute`, `T5.Prove` (`z3_security_performance_suite.py`) |
| **V-05** | [#5](https://github.com/dstadulis/nospeaker/issues/5) (CWE-377/59) | `94116c5` · `render(_:)` (`mkdtemp` `0700` dir + `lstat` `S_IFDIR`/`S_IFREG`, `st_uid == geteuid()`, `st_nlink == 1`) | `TempFileIsolation.shared_tmp_admits_foreign_precreation`, `mkdtemp_0700_blocks_foreign_actors`, `lstat_guard_rejects_symlinks_and_fifos` | `T10.Refute`, `T10.Prove` (`z3_security_performance_suite.py`), `T5B` (`ieee754_and_bv_proofs.smt2`) |
| **V-06** | [#6](https://github.com/dstadulis/nospeaker/issues/6) (CWE-362/479) | `7311fa7`, `88c41b4` · `HeapUnfairLock`, `RunPhase`, `RunController`, `RendererLifecycleCoordinator`, `stopRenderer()`, `onExitRestore()` | `ConcurrencyProtocol.fixed_sleep_shutdown_admits_race`, `join_barrier_prevents_write_after_restore`, `SignalLifecycle.unhardened_split_flags_drop_second_sigint`, `runPhaseTrace_monotonic`, `stopped_is_absorbing`, `two_sigints_guarantee_stopped`, `ConcreteRefinement.runPhase4Trace_simulates`, `two_sigints_stop_runController` | `T6.Refute`, `T6.Prove`, `T12.Refute`, `T12.Prove` (`z3_security_performance_suite.py`) |
| **V-07** | [#7](https://github.com/dstadulis/nospeaker/issues/7) (CWE-150) | `94116c5` · `sanitizeTerminal(_:maxBytes:)`, `fail(_:headline:code:)`, `signOff`, `runMain()` | `TerminalSafety.sanitizeTerminal_escape_free`, `sanitizeTerminal_idempotent` | `T1.Prove`, `T13.Prove` (`z3_security_performance_suite.py`) |
| **V-08** | [#8](https://github.com/dstadulis/nospeaker/issues/8) (CWE-682) | `3f39ae5` · `play(_:ms:level:)`, `ThermalDutyGovernor`, `C./` (Smith's division), `analyse(_:sampleRate:)` (`prefixSq`) | `HardwareActuation.unhardened_signed_amp_overdrive`, `simplex_l1_conservation`, `actuation_band_confinement`, `thermalTrajectory_safe`, `PerformanceComplexity.prefix_sum_121x_faster`, `hybrid_scheduler_zero_deadline_miss` | `T1A.1`..`T1B.2`, `T2A`..`T2C.2` (`ieee754_and_bv_proofs.smt2`), `T2`..`T4`, `T8.Speedup`, `T8.RealTime` (`z3_security_performance_suite.py`) |
| **V-09** | [#9](https://github.com/dstadulis/nospeaker/issues/9) (CWE-404/755) | `f52dd6a`, `94116c5`, `7311fa7` · `IdempotentFDGuard`, `startKeys()` (`5s` `/usr/bin/open -u` cooldown + reap), `build.sh` (`codesign --verify --strict`) | `ConcurrencyProtocol.unhardened_double_silence_loses_tty`, `guarded_fd_restores_for_all_sequences`, `SignalLifecycle.debounced_open_rate_limited`, `SupplyChainGatekeeper.strictBuildSignGate_iff` | `T7.Refute`, `T7.Prove`, `T12.Prove` (`z3_security_performance_suite.py`) |
| **IH-01** | [#10](https://github.com/dstadulis/nospeaker/issues/10) (CWE-252/391) | `94116c5`, `9e2bd22` · `writeAll(_:_:)`, `out(_:)`, `Canvas.changes`, `startRenderer()` (`shown` committed iff `out(frame)` succeeds) | `TerminalWriteLoop.unhardened_out_truncates_ansi_on_eintr`, `hardenedWriteLoop_byte_conservation`, `hardenedWriteLoop_survives_arbitrary_eintr`, `TerminalAndUISafety.ih01_unhardened_canvas_desync`, `ih01_hardened_canvas_coherent` | `T11.Refute`, `T11.Prove`, `T13.Prove` (`z3_security_performance_suite.py`) |
| **IH-02** | [#11](https://github.com/dstadulis/nospeaker/issues/11) (CWE-252/665) | `7311fa7` · `TerminalController.take()`, `TerminalController.restore()` (`termiosSaved` guard, `VMIN = 1`, `VTIME = 0`, `EINTR` retry) | `TerminalAndUISafety.ih02_termios_b0_guard_and_vmin_sound` | `T13.Prove` (`z3_security_performance_suite.py`) |
| **IH-03** | [#12](https://github.com/dstadulis/nospeaker/issues/12) (CWE-403/755) | `7311fa7` · `IdempotentFDGuard.silence()` (`F_DUPFD_CLOEXEC`, `O_CLOEXEC`, checked `dup2`), `fail()` (`fdGuard.unsilence()` + POSIX `writeAll`) | `TerminalAndUISafety.ih03_cloexec_and_fail_unsilence_sound` | `T13.Prove` (`z3_security_performance_suite.py`) |
| **IH-04** | [#13](https://github.com/dstadulis/nospeaker/issues/13) (CWE-20/835) | `9e2bd22` · `TerminalController` (no `?1000h` mouse mode), `startKeys()` (X10 drain, double-`ESC` exit, UTF-8 scalar decoder, `EOF` exit) | `TerminalAndUISafety.ih04_key_and_utf8_parser_sound` | `T13.Prove` (`z3_security_performance_suite.py`) |
| **IH-05** | [#14](https://github.com/dstadulis/nospeaker/issues/14) (CWE-681/129) | `7311fa7`, `9e2bd22` · `drawCaption`, `modPositive`, `safeIndex`, `isVerifiedSingleColumnGlyph`, `formatCountASCII`, `Canvas.put` | `TerminalAndUISafety.ih05_ui_arithmetic_total_and_bounded`, `ConcreteRefinement.isVerifiedSingleColumnGlyph_safe` | `T13.Refute`, `T13.Prove` (`z3_security_performance_suite.py`) |
| **IH-06** | [#15](https://github.com/dstadulis/nospeaker/issues/15) (CWE-400/770) | `9e2bd22` · `terminalSize()` (`ws_col > 0 && ws_row > 0`, clamped `512 × 256`), `fillScreen()` | `DarwinFFIAndClock.ih06_terminal_size_bounded_and_nonzero` | `T14.Refute`, `T14.Prove` (`z3_security_performance_suite.py`) |
| **IH-07** | [#16](https://github.com/dstadulis/nospeaker/issues/16) (CWE-125/404) | `7311fa7` · `macModel()` (`size + 1` zero-initialized buffer + return check), `hasSmartBattery()` (`defer { IOObjectRelease(svc) }`) | `DarwinFFIAndClock.ih07_sysctl_nul_and_iokit_port_sound` | `T14.Prove` (`z3_security_performance_suite.py`) |
| **IH-08** | [#17](https://github.com/dstadulis/nospeaker/issues/17) (CWE-252/131) | `7311fa7` · `speakersMuted()` (`device != kAudioObjectUnknown`, exact `MemoryLayout.size` validation, stereo `[1, 2]` conjunction) | `DarwinFFIAndClock.ih08_speakersMuted_stereo_and_device_sound` | `T14.Prove` (`z3_security_performance_suite.py`) |
| **IH-09** | [#18](https://github.com/dstadulis/nospeaker/issues/18) (CWE-762/404) | `7311fa7` · `MultitouchAPI` (`Unmanaged<CFTypeRef>?` -> `takeRetainedValue()`), `MotorRuntime`, `runMain()` `defer { closeMotor() }` | `DarwinFFIAndClock.ih09_cf_ownership_and_motor_cleanup_sound` | `T14.Prove` (`z3_security_performance_suite.py`) |
| **IH-10** | [#19](https://github.com/dstadulis/nospeaker/issues/19) (CWE-681/190) | `7311fa7` · `deadlineTicks(from:after:)`, `waitUntil(_:allowSkip:)` (`timebase` guard, saturating `UInt64`, `<= 20_000 µs` `useconds_t` slice) | `DarwinFFIAndClock.ih10_mach_clock_and_sleep_safe` | `T14.Prove` (`z3_security_performance_suite.py`) |
| **IH-11** | [#20](https://github.com/dstadulis/nospeaker/issues/20) (CWE-479/459) | `7311fa7`, `88c41b4` · `SignalPipe`, `handleSigInt`, `handleSigTerm`, `startSignalWatcher()`, `signal(SIGPIPE, SIG_IGN)`, `RunController.setCLIMode`, `render(_:)` (`SIGINT` clean abort), `onExitRestore()` | `SignalLPCAndScripts.ih11_signal_mode_and_sigpipe_sound`, `VerifierRound1Closure.h2_sigint_render_clean_abort_sound` | `T15.Prove`, `T16.Prove` (`z3_security_performance_suite.py`) |
| **IH-12** | [#21](https://github.com/dstadulis/nospeaker/issues/21) (CWE-636/183) | `9e2bd22`, `88c41b4` · `isValidVoiceToken`, `extractVoiceNameFromSayLine`, `voiceExists(_:)` (`O_NONBLOCK` `poll`+`read` `<= 5.5s` deadline + `256 KB` cap), `runMain()` (`"--"` partition) | `SubprocessSecurity.voiceExists_fail_closed_iff`, `SignalLPCAndScripts.ih12_exact_voice_and_double_dash_sound`, `VerifierRound1Closure.h1_voiceExists_concurrent_deadline_sound` | `T15.Prove`, `T16.Prove` (`z3_security_performance_suite.py`) |
| **IH-13** | [#22](https://github.com/dstadulis/nospeaker/issues/22) (CWE-682/369) | `3f39ae5` · `lpc(_:order:)` (`abs(k) < 0.999999 && e > 1e-12`), `roots(_:)`, `analyse(_:sampleRate:)` (`0 < rMag < 1`, `bw > 0`, `NaN` RMS -> `0`) | `SignalLPCAndScripts.ih13_unhardened_levinson_hazards`, `levinson_durbin_reflection_stability`, `guardedLevinsonChain_invariant`, `ih13_nan_rms_and_formant_pole_sound` | `T6A.1`, `T6A.2`, `T6B.1`, `T6B.2` (`ieee754_and_bv_proofs.smt2`), `T15.Refute`, `T15.Prove` (`z3_security_performance_suite.py`) |
| **IH-14** | [#23](https://github.com/dstadulis/nospeaker/issues/23) (CWE-276/59/319) | `f52dd6a`, `53b7f64`, `88c41b4` · `play.sh` (`set -eu`, `umask 077`, newline-safe `IFS`, `--proto '=https'`, `--max-redirs 5`, fail-closed `.sha256`, atomic staging, pre-exec `$tmp` rm, safe `/dev/tty`) | `SupplyChainGatekeeper.umask_077_clears_group_and_world`, `full_install_admissible_iff`, `SignalLPCAndScripts.ih14_play_sh_tty_and_hygiene_sound`, `VerifierRound1Closure.h3_sha256_fail_closed_sound` | `T5A`, `T5B` (`ieee754_and_bv_proofs.smt2`), `T9.Prove`, `T15.Prove`, `T16.Refute`, `T16.Prove` (`z3_security_performance_suite.py`) |
| **IH-15** | [#24](https://github.com/dstadulis/nospeaker/issues/24) (CWE-754/459/347) | `f52dd6a`, `53b7f64`, `88c41b4` · `build.sh` (`set -eu`, newline-safe `IFS`, `[ -d nospeaker ]` guard, strict `mode` check, 40-hex SHA-1 cert identity, staged notarization zip promotion) | `SupplyChainGatekeeper.strictBuildSignGate_iff`, `SignalLPCAndScripts.ih15_build_sh_strict_mode_and_atomic_dist_iff`, `VerifierRound1Closure.h3_safe_atomic_target_iff` | `T15.Prove` (`z3_security_performance_suite.py`) |
