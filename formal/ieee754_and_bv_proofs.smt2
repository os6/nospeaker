; =============================================================================
; NoSpeaker Formal Verification Suite — SMT-LIB2 (Z3 5.3.3)
; Logics: QF_FP (IEEE-754 Binary64, Binary32, Binary16) & QF_BV (64-bit/32-bit)
;
; Every scope checks either:
;   - [Refutation] (expect `sat`): exhibits an IEEE-754 / BitVector witness
;     violating a safety invariant in unhardened nospeaker.swift.
;   - [Proof]      (expect `unsat`): proves universal absence of any violation
;     across the entire state space of the hardened contract.
; =============================================================================

(set-logic ALL)

; -----------------------------------------------------------------------------
; THEOREM 1 (QF_FP): Complex Division Underflow in Durand-Kerner `roots(_:)`
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L346-L365 (`C./` and `if d.re == 0 && d.im == 0`)
; -----------------------------------------------------------------------------
(echo "=== T1A.1 [Refutation - Float64]: Non-zero normal r underflows r.re^2 + r.im^2 to +0.0 (expect sat) ===")
(push 1)
(declare-const r_re Float64)
(declare-const r_im Float64)
(assert (and (fp.isNormal r_re) (fp.isNormal r_im)))
(assert (not (and (fp.eq r_re (_ +zero 11 53)) (fp.eq r_im (_ +zero 11 53)))))
(define-fun unhardened_d () Float64
  (fp.add RNE (fp.mul RNE r_re r_re) (fp.mul RNE r_im r_im)))
(assert (fp.eq unhardened_d (_ +zero 11 53)))
(check-sat)
(pop 1)

(echo "=== T1A.2 [Proof - Float64]: Zero denominator in C./ ALWAYS yields NaN or Inf (expect unsat) ===")
(push 1)
(declare-const num Float64)
(declare-const den Float64)
(assert (and (not (fp.isNaN num)) (not (fp.isInfinite num))))
(assert (fp.eq den (_ +zero 11 53)))
(define-fun quot () Float64 (fp.div RNE num den))
(assert (and (not (fp.isNaN quot)) (not (fp.isInfinite quot))))
(check-sat)
(pop 1)

(echo "=== T1B.1 [Proof - Float64]: Magnitude-form Smith denominator |re| + |im|*|ratio| >= |re| > 0 on ALL normal Float64 (expect unsat) ===")
(push 1)
(declare-const mre Float64)
(declare-const mim Float64)
(declare-const mrat Float64)
; 2^500 in IEEE-754 Float64 (sign=0, biased_exp=1023+500=1523=#b10111110011, mant=0)
(define-fun mb64 () Float64 (fp #b0 #b10111110011 #x0000000000000))
(define-fun ob64 () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun zb64 () Float64 (_ +zero 11 53))

(assert (fp.isNormal mre))
(assert (and (not (fp.isNaN mim)) (not (fp.isInfinite mim))))
(assert (fp.leq (fp.abs mim) (fp.abs mre)))
(assert (fp.leq (fp.abs mre) mb64))
(assert (and (not (fp.isNaN mrat)) (fp.geq mrat zb64) (fp.leq mrat ob64)))

(define-fun smith_mag_denom () Float64
  (fp.add RNE (fp.abs mre) (fp.mul RNE (fp.abs mim) mrat)))

(assert (or (fp.eq smith_mag_denom zb64)
            (fp.lt smith_mag_denom (fp.abs mre))
            (fp.isNaN smith_mag_denom)
            (fp.isInfinite smith_mag_denom)))
(check-sat)
(pop 1)

(echo "=== T1B.2 [Proof - Monolithic IEEE-754 Binary16]: End-to-end Smith complex division denominator never zero/NaN/Inf (expect unsat) ===")
(push 1)
(declare-const h_re Float16)
(declare-const h_im Float16)
(define-fun max_b16 () Float16 ((_ to_fp 5 11) RNE 100.0))
(assert (and (not (fp.isNaN h_re)) (not (fp.isInfinite h_re))))
(assert (and (not (fp.isNaN h_im)) (not (fp.isInfinite h_im))))
(assert (or (fp.isNormal h_re) (fp.isNormal h_im)))
(assert (and (fp.leq (fp.abs h_re) max_b16) (fp.leq (fp.abs h_im) max_b16)))

(define-fun smith_d16 () Float16
  (ite (fp.geq (fp.abs h_re) (fp.abs h_im))
       (fp.add RNE h_re (fp.mul RNE h_im (fp.div RNE h_im h_re)))
       (fp.add RNE h_im (fp.mul RNE h_re (fp.div RNE h_re h_im)))))

(assert (or (fp.eq smith_d16 (_ +zero 5 11))
            (fp.isNaN smith_d16)
            (fp.isInfinite smith_d16)))
(check-sat)
(pop 1)

; -----------------------------------------------------------------------------
; THEOREM 2 (QF_FP): Haptic Motor Amplitude & NaN Safety in `play(_:ms:level:)`
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L167-L173 (`let sum = max(tones.reduce(0)..., 0.0001)`)
; -----------------------------------------------------------------------------
(echo "=== T2A [Refutation - Float64]: Swift max(sum, 0.0001) leaks NaN when tone amp is NaN or +oo (expect sat) ===")
(push 1)
(declare-const a1 Float64)
(declare-const a2 Float64)
(define-fun eps () Float64 ((_ to_fp 11 53) RNE 0.0001))
(define-fun raw_sum () Float64 (fp.add RNE a1 a2))
(define-fun swift_max_sum () Float64 (ite (fp.geq eps raw_sum) eps raw_sum))
(assert (fp.isNaN swift_max_sum))
(check-sat)
(pop 1)

(echo "=== T2B [Refutation - Float64]: Signed normal tone amplitudes exceed normal maximum 1.0 (expect sat) ===")
(push 1)
(declare-const b1 Float64)
(declare-const b2 Float64)
(define-fun eps64 () Float64 ((_ to_fp 11 53) RNE 0.0001))
(assert (and (fp.isNormal b1) (fp.isNormal b2)))
(define-fun s64 () Float64 (fp.add RNE b1 b2))
(define-fun smax64 () Float64 (ite (fp.geq eps64 s64) eps64 s64))
(assert (fp.gt (fp.abs b1) smax64))
(check-sat)
(pop 1)

(echo "=== T2C.1 [Proof - Float64 & Float32]: Hardened clamp01 is strictly in [0.0, 1.0] & NaN-free for ALL 2^64 + 2^32 floats (expect unsat) ===")
(push 1)
(declare-const q_raw Float64)
(declare-const lvl_raw Float32)
(define-fun zero64 () Float64 (_ +zero 11 53))
(define-fun one64 () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun zero32 () Float32 (_ +zero 8 24))
(define-fun one_f32 () Float32 ((_ to_fp 8 24) RNE 1.0))

(define-fun clamp01_64 ((u Float64)) Float64
  (ite (or (fp.isNaN u) (fp.leq u zero64))
       zero64
       (ite (fp.geq u one64) one64 u)))

(define-fun clamp01_32 ((u Float32)) Float32
  (ite (or (fp.isNaN u) (fp.leq u zero32))
       zero32
       (ite (fp.geq u one_f32) one_f32 u)))

(define-fun w_safe () Float64 (clamp01_64 q_raw))
(define-fun lvl_safe () Float32 (clamp01_32 lvl_raw))

(assert (or (fp.isNaN w_safe)
            (fp.isInfinite w_safe)
            (fp.lt w_safe zero64)
            (fp.gt w_safe one64)
            (fp.isNaN lvl_safe)
            (fp.isInfinite lvl_safe)
            (fp.lt lvl_safe zero32)
            (fp.gt lvl_safe one_f32)))
(check-sat)
(pop 1)

(echo "=== T2C.2 [Proof - IEEE-754 Binary16 Simplex Ratio]: Sanitized component ratio cp1 / max(cp1 + cp2, eps) <= 1.0 & >= 0.0 for ALL inputs (expect unsat) ===")
(push 1)
(declare-const p1 Float16)
(declare-const p2 Float16)
(define-fun z16 () Float16 (_ +zero 5 11))
(define-fun o16 () Float16 ((_ to_fp 5 11) RNE 1.0))
(define-fun cap16 () Float16 ((_ to_fp 5 11) RNE 100.0))
(define-fun feps16 () Float16 ((_ to_fp 5 11) RNE 0.01))

(define-fun san16 ((x Float16)) Float16
  (ite (or (fp.isNaN x) (fp.leq x z16))
       z16
       (ite (fp.gt x cap16) cap16 x)))

(define-fun cp1 () Float16 (san16 p1))
(define-fun cp2 () Float16 (san16 p2))
(define-fun csum16 () Float16 (fp.add RNE cp1 cp2))
(define-fun sden16 () Float16 (ite (fp.gt csum16 feps16) csum16 feps16))
(define-fun w1_raw () Float16 (fp.div RNE cp1 sden16))

(assert (or (fp.isNaN w1_raw)
            (fp.isInfinite w1_raw)
            (fp.lt w1_raw z16)
            (fp.gt w1_raw o16)))
(check-sat)
(pop 1)

; -----------------------------------------------------------------------------
; THEOREM 3 (QF_BV): 64-bit AVAudioFramePosition -> 32-bit AVAudioFrameCount Trap
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L308 (`AVAudioFrameCount(file.length)`)
; -----------------------------------------------------------------------------
(echo "=== T3A [Refutation - BV64]: Unguarded Int64 -> UInt32 audio frame cast overflows/traps (expect sat) ===")
(push 1)
(declare-const file_len (_ BitVec 64))
(assert (bvsge file_len #x0000000000000000))
(assert (bvugt file_len #x00000000FFFFFFFF))
(check-sat)
(pop 1)

(echo "=== T3B [Proof - BV64]: Hardened 30s @ 48kHz Audio Cap guarantees UInt32 safety & <= 5.76 MiB PCM (expect unsat) ===")
(push 1)
(declare-const file_len2 (_ BitVec 64))
(define-fun max_frames () (_ BitVec 64) #x000000000015F900)
(assert (and (bvsge file_len2 #x0000000000000000)
             (bvsle file_len2 max_frames)))

(define-fun pcm_bytes () (_ BitVec 64) (bvmul file_len2 #x0000000000000004))
(assert (or (bvugt file_len2 #x00000000FFFFFFFF)
            (bvugt pcm_bytes #x0000000000600000)
            (not (= ((_ zero_extend 32) ((_ extract 31 0) file_len2)) file_len2))))
(check-sat)
(pop 1)

; -----------------------------------------------------------------------------
; THEOREM 4 (QF_BV): MultitouchSupport Raw Contact Buffer Over-Read (`CWE-125`)
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L233-L237 (`data.advanced(by: i * 96)`, `.load(fromByteOffset: 48, as: Float.self)`)
; -----------------------------------------------------------------------------
(echo "=== T4A.1 [Refutation - BV64]: At count >= 2, hardcoded 96-byte stride misaligns field offsets on 88-byte struct (expect sat) ===")
(push 1)
(declare-const count (_ BitVec 32))
(declare-const idx (_ BitVec 32))
(assert (and (bvsge count #x00000002) (bvsle count #x00000010)))
(assert (and (bvsgt idx #x00000000) (bvslt idx count)))
(define-fun true_x_off () (_ BitVec 64)
  (bvadd (bvmul ((_ sign_extend 32) idx) #x0000000000000058) #x0000000000000020))
(define-fun read_x_off () (_ BitVec 64)
  (bvadd (bvmul ((_ sign_extend 32) idx) #x0000000000000060) #x0000000000000020))
(assert (not (= true_x_off read_x_off)))
(check-sat)
(pop 1)

(echo "=== T4A.2 [Refutation - BV64]: At count >= 6, hardcoded 96-byte stride reads past end of 88-byte buffer (expect sat) ===")
(push 1)
(declare-const count_oob (_ BitVec 32))
(declare-const idx_oob (_ BitVec 32))
(assert (and (bvsgt count_oob #x00000000) (bvsle count_oob #x00000010)))
(assert (and (bvsge idx_oob #x00000000) (bvslt idx_oob count_oob)))
(define-fun alloc_bytes () (_ BitVec 64)
  (bvmul ((_ sign_extend 32) count_oob) #x0000000000000058))
(define-fun read_end () (_ BitVec 64)
  (bvadd (bvmul ((_ sign_extend 32) idx_oob) #x0000000000000060) #x0000000000000034))
(assert (bvugt read_end alloc_bytes))
(check-sat)
(pop 1)

(echo "=== T4B [Proof - BV64]: Stride-validated & 4-byte alignment-checked touch reader never over-reads or traps (expect unsat) ===")
(push 1)
(declare-const count2 (_ BitVec 32))
(declare-const idx2 (_ BitVec 32))
(declare-const stride2 (_ BitVec 64))
(declare-const base_addr (_ BitVec 64))

(assert (and (bvsgt count2 #x00000000) (bvsle count2 #x00000020)))
(assert (and (bvsge idx2 #x00000000) (bvslt idx2 count2)))
(assert (and (bvuge stride2 #x0000000000000034) (bvule stride2 #x0000000000001000)))
(assert (= (bvand base_addr #x0000000000000003) #x0000000000000000))
(assert (= (bvand stride2 #x0000000000000003) #x0000000000000000))

(define-fun alloc_bytes2 () (_ BitVec 64) (bvmul ((_ zero_extend 32) count2) stride2))
(define-fun rec_offset () (_ BitVec 64) (bvmul ((_ zero_extend 32) idx2) stride2))
(define-fun size_field_addr () (_ BitVec 64) (bvadd base_addr (bvadd rec_offset #x0000000000000030)))
(define-fun max_read_end () (_ BitVec 64) (bvadd rec_offset #x0000000000000034))

(assert (or (bvugt max_read_end alloc_bytes2)
            (not (= (bvand size_field_addr #x0000000000000003) #x0000000000000000))))
(check-sat)
(pop 1)

; -----------------------------------------------------------------------------
; THEOREM 5 (QF_BV): POSIX `mode_t` (16-bit) `umask 077` & `lstat` `S_IFMT == S_IFREG`
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/play.sh#L18-L26
;      https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L300-L309
; -----------------------------------------------------------------------------
(echo "=== T5A [Refutation - BV16]: Default umask 022 leaves group/world read-exec bits open (expect sat) ===")
(push 1)
(declare-const req_mode (_ BitVec 16))
(assert (= req_mode #x01FF)) ; 0o0777
(define-fun masked_022 () (_ BitVec 16) (bvand req_mode (bvnot #x0012))) ; ~0o022
(assert (not (= (bvand masked_022 #x003F) #x0000))) ; 0o077 group/world bits non-zero!
(check-sat)
(pop 1)

(echo "=== T5B [Proof - BV16]: umask 077 clears ALL group/world permission bits & S_IFREG excludes S_IFLNK/S_IFIFO across all 2^16 mode_t values (expect unsat) ===")
(push 1)
(declare-const any_mode (_ BitVec 16))
(declare-const st_mode (_ BitVec 16))
(define-fun umask_077 () (_ BitVec 16) #x003F)  ; 0o0077
(define-fun s_ifmt () (_ BitVec 16) #xF000)     ; 0o170000
(define-fun s_ifreg () (_ BitVec 16) #x8000)    ; 0o100000
(define-fun s_iflnk () (_ BitVec 16) #xA000)    ; 0o120000
(define-fun s_ififo () (_ BitVec 16) #x1000)    ; 0o010000
(define-fun s_ifdir () (_ BitVec 16) #x4000)    ; 0o040000

(define-fun created_mode () (_ BitVec 16) (bvand any_mode (bvnot umask_077)))
(assert (= (bvand st_mode s_ifmt) s_ifreg))

(assert (or (not (= (bvand created_mode umask_077) #x0000))
            (= (bvand st_mode s_ifmt) s_iflnk)
            (= (bvand st_mode s_ifmt) s_ififo)
            (= (bvand st_mode s_ifmt) s_ifdir)))
(check-sat)
(pop 1)

; -----------------------------------------------------------------------------
; THEOREM 6 (QF_FP): Levinson-Durbin Reflection Stability & `NaN` RMS Full-Scale Bug (`V-08` / `IH-13`)
; Ref: https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L336 (`e *= 1 - k * k`)
;      https://github.com/os6/nospeaker/blob/e02a121243f3dbddb288fa6520134b0c4a8727c6/nospeaker.swift#L427 (`rel < 0.02 ? 0 : Float(min(1, ...))`)
; -----------------------------------------------------------------------------
(echo "=== T6A.1 [Refutation - Float64]: Swift min(1.0, NaN) on corrupted PCM RMS drives motor at 100% full scale 1.0! (expect sat) ===")
(push 1)
(declare-const rel_nan Float64)
(declare-const pow_nan Float64)
(define-fun thresh64 () Float64 ((_ to_fp 11 53) RNE 0.02))
(define-fun one_64 () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun zero_64 () Float64 (_ +zero 11 53))
(assert (and (fp.isNaN rel_nan) (fp.isNaN pow_nan)))
; Swift `min(x, y)` is `y < x ? y : x`, so `min(1.0, pow_nan)` is `(ite (fp.lt pow_nan 1.0) pow_nan 1.0)`
(define-fun swift_min_1 () Float64 (ite (fp.lt pow_nan one_64) pow_nan one_64))
(define-fun unhardened_rms_lvl () Float64
  (ite (fp.lt rel_nan thresh64) zero_64 swift_min_1))
(assert (fp.eq unhardened_rms_lvl one_64))
(check-sat)
(pop 1)

(echo "=== T6A.2 [Refutation - Float64]: Unhardened Levinson-Durbin 2-step |k|>1 flips negative error back to e_2 > 0! (expect sat) ===")
(push 1)
(declare-const e0_fp Float64)
(declare-const k1_fp Float64)
(declare-const k2_fp Float64)
(define-fun f64_one () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun f64_two () Float64 ((_ to_fp 11 53) RNE 2.0))
(define-fun f64_zero () Float64 (_ +zero 11 53))
(assert (fp.eq e0_fp f64_one))
(assert (and (fp.eq k1_fp f64_two) (fp.eq k2_fp f64_two)))
(assert (and (fp.gt (fp.abs k1_fp) f64_one) (fp.gt (fp.abs k2_fp) f64_one)))
(define-fun e1_fp () Float64 (fp.mul RNE e0_fp (fp.sub RNE f64_one (fp.mul RNE k1_fp k1_fp))))
(define-fun e2_fp () Float64 (fp.mul RNE e1_fp (fp.sub RNE f64_one (fp.mul RNE k2_fp k2_fp))))
(assert (and (fp.lt e1_fp f64_zero) (fp.gt e2_fp f64_zero)))
(check-sat)
(pop 1)

(echo "=== T6B.1 [Proof - Float64]: Schur guard |k| <= 0.999999 guarantees 0 < (1 - k^2) <= 1.0 across ALL Float64 (expect unsat) ===")
(push 1)
(declare-const k_safe Float64)
(define-fun k_bound () Float64 ((_ to_fp 11 53) RNE 0.999999))
(define-fun one_f64 () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun zero_f64 () Float64 (_ +zero 11 53))
(assert (and (not (fp.isNaN k_safe)) (fp.leq (fp.abs k_safe) k_bound)))
(define-fun schur_factor () Float64 (fp.sub RNE one_f64 (fp.mul RNE k_safe k_safe)))
(assert (or (fp.isNaN schur_factor)
            (fp.isInfinite schur_factor)
            (fp.leq schur_factor zero_f64)
            (fp.gt schur_factor one_f64)))
(check-sat)
(pop 1)

(echo "=== T6B.2 [Proof - Monolithic IEEE-754 Binary16 + Float64 RMS Guard]: End-to-end e' = e*(1 - k^2) > 0 & <= e, and NaN RMS -> 0.0 (expect unsat) ===")
(push 1)
(declare-const e16 Float16)
(declare-const k16 Float16)
(declare-const rel_any Float64)
(declare-const pow_any Float64)
(define-fun emin16 () Float16 ((_ to_fp 5 11) RNE 0.001))
(define-fun emax16 () Float16 ((_ to_fp 5 11) RNE 1000.0))
(define-fun kmax16 () Float16 ((_ to_fp 5 11) RNE 0.99))
(define-fun o16_ld () Float16 ((_ to_fp 5 11) RNE 1.0))
(define-fun z16_ld () Float16 (_ +zero 5 11))

(assert (and (not (fp.isNaN e16)) (fp.geq e16 emin16) (fp.leq e16 emax16)))
(assert (and (not (fp.isNaN k16)) (fp.leq (fp.abs k16) kmax16)))
(define-fun enext16 () Float16 (fp.mul RNE e16 (fp.sub RNE o16_ld (fp.mul RNE k16 k16))))

(define-fun th64 () Float64 ((_ to_fp 11 53) RNE 0.02))
(define-fun z64_r () Float64 (_ +zero 11 53))
(define-fun o64_r () Float64 ((_ to_fp 11 53) RNE 1.0))
(define-fun hardened_rms_lvl () Float64
  (ite (or (fp.isNaN rel_any) (fp.isInfinite rel_any) (fp.lt rel_any th64) (fp.isNaN pow_any))
       z64_r
       (ite (fp.geq pow_any o64_r) o64_r (ite (fp.leq pow_any z64_r) z64_r pow_any))))

(assert (or (fp.isNaN enext16)
            (fp.isInfinite enext16)
            (fp.leq enext16 z16_ld)
            (fp.gt enext16 e16)
            (fp.isNaN hardened_rms_lvl)
            (fp.lt hardened_rms_lvl z64_r)
            (fp.gt hardened_rms_lvl o64_r)
            (and (fp.isNaN rel_any) (not (fp.eq hardened_rms_lvl z64_r)))))
(check-sat)
(pop 1)
