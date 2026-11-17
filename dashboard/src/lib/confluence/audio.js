// Synthesizer provides instant latency-free feedback without loading external audio assets
export function createAudioEngine() {
  let audio = null;
  let master = null;
  let soundOn = true;

  function init() {
    if (audio) return;
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      audio = new AudioCtx();
      master = audio.createGain();
      master.gain.value = soundOn ? 0.9 : 0;
      master.connect(audio.destination);
    } catch {
      // AudioContext unavailable in headless or restricted environments
    }
  }

  function beep(f0, f1, dur, type, vol) {
    if (!audio || !soundOn || audio.state !== 'running') return;
    const t = audio.currentTime;
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(f0, t);
    osc.frequency.exponentialRampToValueAtTime(Math.max(30, f1), t + dur);
    gain.gain.setValueAtTime(vol, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(gain);
    gain.connect(master);
    osc.start(t);
    osc.stop(t + dur + 0.02);
  }

  function resume() {
    if (audio && audio.state === 'suspended') {
      audio.resume();
    }
  }

  function setMuted(muted) {
    soundOn = !muted;
    if (master) master.gain.value = soundOn ? 0.9 : 0;
  }

  return {
    init,
    resume,
    setMuted,
    isSoundOn: () => soundOn,
    wall: () => beep(660, 880, 0.12, 'sine', 0.06),
    held: () => beep(520, 540, 0.09, 'triangle', 0.07),
    pull: () => beep(200, 110, 0.14, 'sine', 0.08),
    brk: () => beep(240, 80, 0.18, 'sawtooth', 0.045),
    kill: () => beep(440, 90, 0.3, 'square', 0.05),
    ui: () => beep(900, 880, 0.03, 'sine', 0.025)
  };
}
