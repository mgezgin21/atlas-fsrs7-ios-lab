//! Isolated, untrusted-input-checked FFI feasibility boundary.
//! No Atlas dependencies, no file/database access, no telemetry.
//! This C ABI is a PROTOTYPE and MUST be versioned and reviewed before production.
use fsrs::{FSRS, FSRS6_DEFAULT_PARAMETERS, DEFAULT_PARAMETERS, MemoryState, ModelVersion};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct AtlasState {
    pub stability: f32,
    pub difficulty: f32,
    pub stability_fast: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct AtlasChoice {
    pub memory: AtlasState,
    pub interval_days: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct AtlasNext {
    pub again: AtlasChoice,
    pub hard: AtlasChoice,
    pub good: AtlasChoice,
    pub easy: AtlasChoice,
}

impl From<MemoryState> for AtlasState {
    fn from(x: MemoryState) -> Self {
        Self {
            stability: x.stability,
            difficulty: x.difficulty,
            stability_fast: x.stability_fast,
        }
    }
}

impl From<AtlasState> for MemoryState {
    fn from(x: AtlasState) -> Self {
        Self {
            stability: x.stability,
            difficulty: x.difficulty,
            stability_fast: x.stability_fast,
        }
    }
}

fn is_valid_state(s: AtlasState) -> bool {
    s.stability.is_finite() && s.stability > 0.0 && s.stability <= 36500.0
        && s.stability_fast.is_finite() && s.stability_fast > 0.0 && s.stability_fast <= 36500.0
        && s.difficulty.is_finite() && (1.0..=10.0).contains(&s.difficulty)
}

/// ABI 1. Return 7 only if the pinned source's default actually selects FSRS-7.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_fsrs7_engine_version() -> u32 {
    if FSRS::default().version() == ModelVersion::Fsrs7 { 7 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_fsrs7_abi_version() -> u32 { 1 }

#[unsafe(no_mangle)]
pub extern "C" fn atlas_fsrs7_parameter_count() -> u32 { DEFAULT_PARAMETERS.len() as u32 }

#[unsafe(no_mangle)]
pub extern "C" fn atlas_fsrs7_state_size() -> usize { std::mem::size_of::<AtlasState>() }

#[unsafe(no_mangle)]
pub extern "C" fn atlas_fsrs7_output_size() -> usize { std::mem::size_of::<AtlasNext>() }

/// Compute 4 possible outcomes from the pinned 34-parameter default model.
/// elapsed_days is FRACTIONAL; e.g. 10 minutes = 10.0 / 1440.0.
/// Previous state = NULL means new. Outputs are written ONLY on success.
/// Returns: 0 OK, -1 invalid output, -2 input, -3 wrong upstream model,
/// -4 invalid model state or computation. Never writes into Atlas databases.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn atlas_fsrs7_next(
    previous: *const AtlasState,
    elapsed_days: f32,
    desired_retention: f32,
    output: *mut AtlasNext,
) -> i32 {
    if output.is_null() { return -1; }
    if !elapsed_days.is_finite() || !(0.0..=36500.0).contains(&elapsed_days)
        || !desired_retention.is_finite() || !(0.8..=0.97).contains(&desired_retention)
    { return -2; }
    // SAFETY: C caller must supply a valid properly aligned pointer to AtlasState,
    // or null. Invalid pointers cannot be validated by any C ABI implementation.
    let before = if previous.is_null() { None } else {
        let state = unsafe { *previous };
        if !is_valid_state(state) { return -2; }
        Some(state.into())
    };
    let model = FSRS::default();
    if model.version() != ModelVersion::Fsrs7 { return -3; }
    compute_next_with_model(&model, before, desired_retention, elapsed_days, output)
}

/// Same C ABI with custom 34-element FSRS-7 profile (no optimizer here).
/// Required for a production-capable future parameter adapter. `parameters`
/// must address 34 readable floats. Returns -5 for invalid custom profile.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn atlas_fsrs7_next_with_parameters(
    parameters: *const f32,
    parameter_count: u32,
    previous: *const AtlasState,
    elapsed_days: f32,
    desired_retention: f32,
    output: *mut AtlasNext,
) -> i32 {
    if parameters.is_null() || parameter_count != 34 { return -5; }
    if output.is_null() { return -1; }
    if !elapsed_days.is_finite() || !(0.0..=36500.0).contains(&elapsed_days)
        || !desired_retention.is_finite() || !(0.8..=0.97).contains(&desired_retention)
    { return -2; }
    let params = unsafe { std::slice::from_raw_parts(parameters, parameter_count as usize) };
    if params.iter().any(|x| !x.is_finite()) { return -5; }
    let before = if previous.is_null() { None } else {
        let state = unsafe { *previous };
        if !is_valid_state(state) { return -2; }
        Some(state.into())
    };
    let Ok(model) = FSRS::new(params) else { return -5; };
    if model.version() != ModelVersion::Fsrs7 { return -3; }
    compute_next_with_model(&model, before, desired_retention, elapsed_days, output)
}

fn compute_next_with_model(
    model: &FSRS, before: Option<MemoryState>,
    desired_retention: f32, elapsed_days: f32, output: *mut AtlasNext,
) -> i32 {
    let Ok(next) = model.next_states_with_elapsed_days(before, desired_retention, elapsed_days) else {
        return -4;
    };
    let converted = AtlasNext {
        again: AtlasChoice {memory: next.again.memory.into(), interval_days: next.again.interval},
        hard: AtlasChoice {memory: next.hard.memory.into(), interval_days: next.hard.interval},
        good: AtlasChoice {memory: next.good.memory.into(), interval_days: next.good.interval},
        easy: AtlasChoice {memory: next.easy.memory.into(), interval_days: next.easy.interval},
    };
    for c in [converted.again, converted.hard, converted.good, converted.easy] {
        if !is_valid_state(c.memory) || !c.interval_days.is_finite()
            || c.interval_days <= 0.0 || c.interval_days > 36500.0 { return -4; }
    }
    // SAFETY: caller guarantees a non-null writable pointer for AtlasNext.
    unsafe { *output = converted; }
    0
}

/// Test-only high-value checks; these MUST pass on a real Rust runner.
#[cfg(test)]
mod tests {
    use super::*;
    fn sample(out: &mut AtlasNext) -> i32 {
        unsafe { atlas_fsrs7_next(std::ptr::null(), 0.0, 0.9, out) }
    }
    #[test]
    fn pinned_upstream_is_fsrs7_not_fsrs6() {
        assert_eq!(atlas_fsrs7_engine_version(), 7);
        assert_eq!(atlas_fsrs7_abi_version(), 1);
        assert_eq!(atlas_fsrs7_parameter_count(), 34);
        assert_eq!(FSRS::default().version(), ModelVersion::Fsrs7);
        assert_eq!(FSRS::new(&FSRS6_DEFAULT_PARAMETERS).unwrap().version(), ModelVersion::Fsrs6);
    }
    #[test]
    fn ffi_layout_is_stable() {
        assert_eq!(atlas_fsrs7_state_size(), 12);
        assert_eq!(std::mem::size_of::<AtlasChoice>(), 16);
        assert_eq!(atlas_fsrs7_output_size(), 64);
    }
    #[test]
    fn golden_first_review_from_upstream_documentation() {
        let mut out = AtlasNext::default();
        assert_eq!(sample(&mut out), 0);
        // Reference: fsrs-rs pinned src/inference.rs next_states() doc example.
        for (got, stability, difficulty, fast, interval) in [
            (out.again, 0.1104, 6.1686, 0.08832, 3.8275626e-5),
            (out.hard, 2.2395, 5.261278, 1.7916001, 0.5974598),
            (out.good, 3.9221, 3.5307243, 3.13768, 4.7777247),
            (out.easy, 11.7841, 1.0, 9.427279, 53.869392),
        ] {
            assert!((got.memory.stability-stability).abs() < 0.025, "stability: {:?}",got);
            assert!((got.memory.difficulty-difficulty).abs() < 0.025, "difficulty: {:?}",got);
            assert!((got.memory.stability_fast-fast).abs() < 0.025,"fast: {:?}",got);
            assert!((got.interval_days-interval).abs() < 0.1,"interval: {:?}",got);
        }
    }
    #[test]
    fn all_ratings_and_fractional_same_day_history() {
        let mut out = AtlasNext::default();
        assert_eq!(sample(&mut out),0);
        let mut state = out.good.memory;
        for (i, elapsed) in [10.0f32/1440.0,1.0/24.0,1.0,3.5,15.0,0.0].iter().enumerate() {
            assert_eq!(unsafe{atlas_fsrs7_next(&state,*elapsed,0.9,&mut out)},0,"step {i}");
            let selected=[out.again, out.hard, out.good, out.easy][i%4];
            state = selected.memory;
            assert!(is_valid_state(state));
        }
    }
    #[test]
    fn invalid_inputs_fail_without_changing_output() {
        let mut out = AtlasNext::default();
        assert_eq!(unsafe{atlas_fsrs7_next(std::ptr::null(),0.0,0.9,std::ptr::null_mut())},-1);
        assert_eq!(unsafe{atlas_fsrs7_next(std::ptr::null(),f32::NAN,0.9,&mut out)},-2);
        assert_eq!(unsafe{atlas_fsrs7_next(std::ptr::null(),0.0,0.99,&mut out)},-2);
        assert_eq!(unsafe{atlas_fsrs7_next(std::ptr::null(),-1.0,0.9,&mut out)},-2);
        let bad=AtlasState{stability:0.0,difficulty:5.0,stability_fast:1.0};
        assert_eq!(unsafe{atlas_fsrs7_next(&bad,1.0,0.9,&mut out)},-2);
        assert_eq!(out.good.interval_days,0.0);
    }
    #[test]
    fn profile_api_34_params_and_21_param_rejection() {
        let mut out = AtlasNext::default();
        let code = unsafe { atlas_fsrs7_next_with_parameters(
            DEFAULT_PARAMETERS.as_ptr(), 34, std::ptr::null(), 0.0, 0.9, &mut out
        ) };
        assert_eq!(code, 0);
        assert!((out.good.memory.stability - 3.9221).abs() < 0.025);
        assert_eq!(unsafe { atlas_fsrs7_next_with_parameters(
            FSRS6_DEFAULT_PARAMETERS.as_ptr(), 21, std::ptr::null(), 0.0, 0.9, &mut out
        ) }, -5);
        assert_eq!(unsafe { atlas_fsrs7_next_with_parameters(
            std::ptr::null(), 34, std::ptr::null(), 0.0, 0.9, &mut out
        ) }, -5);
    }
    #[test]
    fn fifty_sequential_reviews_with_mixed_intervals() {
        let mut out=AtlasNext::default();
        assert_eq!(sample(&mut out), 0);
        let mut state=out.good.memory;
        for i in 0..50 {
            let elapsed=match i%5 {0=>10.0/1440.0,1=>1.0/24.0,2=>1.0,3=>7.0,_=>30.0};
            assert_eq!(unsafe{atlas_fsrs7_next(&state,elapsed,0.9,&mut out)},0);
            let rating=match i%4 {0=>out.again,1=>out.hard,2=>out.good,_=>out.easy};
            assert!(is_valid_state(rating.memory));
            state=rating.memory;
        }
    }
    #[test]
    fn ffi_matches_direct_core_and_state_roundtrip() {
        let mut out=AtlasNext::default();
        assert_eq!(sample(&mut out),0);
        let direct=FSRS::default().next_states_with_elapsed_days(None,0.9,0.0).unwrap();
        assert_eq!(out.good.memory, AtlasState::from(direct.good.memory));
        assert_eq!(out.good.interval_days,direct.good.interval);
        let persisted=[out.good.memory.stability,out.good.memory.difficulty,out.good.memory.stability_fast];
        let restored=AtlasState{stability:persisted[0],difficulty:persisted[1],stability_fast:persisted[2]};
        assert_eq!(restored,out.good.memory);
        assert_eq!(unsafe{atlas_fsrs7_next(&restored,10.0/1440.0,0.9,&mut out)},0);
    }
}
