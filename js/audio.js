/* =====================================================================
   Arbor Simulator · audio.js
   Every sound is synthesized with the Web Audio API (no sound files).
   ===================================================================== */
'use strict';

const SND={ctx:null,master:null,on:true};
function sndInit(){if(SND.ctx)return;const C=window.AudioContext||window.webkitAudioContext;if(!C)return;const ctx=new C();SND.ctx=ctx;
  SND.master=ctx.createGain();SND.master.gain.value=.7;SND.muff=ctx.createBiquadFilter();SND.muff.type='lowpass';SND.muff.frequency.value=20000;SND.muffG=ctx.createGain();SND.muffG.gain.value=1;
  SND.master.connect(SND.muff);SND.muff.connect(SND.muffG);SND.muffG.connect(ctx.destination);
  const len=ctx.sampleRate*2,buf=ctx.createBuffer(1,len,ctx.sampleRate),d=buf.getChannelData(0);for(let i=0;i<len;i++)d[i]=Math.random()*2-1;SND.noise=buf;
  const cur=new Float32Array(256);for(let i=0;i<256;i++){const x=i/128-1;cur[i]=Math.tanh(x*3);}SND.curve=cur;}
// ear muffs: cut the highs and drop the level, the way real hearing protection does
function setMuffs(on){if(!SND.ctx)return;const t=SND.ctx.currentTime;SND.muff.frequency.setTargetAtTime(on?650:20000,t,.08);SND.muffG.gain.setTargetAtTime(on?.38:1,t,.08);}
function noiseSrc(){const s=SND.ctx.createBufferSource();s.buffer=SND.noise;s.loop=true;return s;}
// one-shot helper: filtered noise burst
function sNoise(dur,freq,q,vol,type,delay){if(!SND.ctx)return;const c=SND.ctx,t=c.currentTime+(delay||0);const s=noiseSrc(),f=c.createBiquadFilter(),g=c.createGain();
  f.type=type||'bandpass';f.frequency.value=freq;f.Q.value=q||1;g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(vol,t+.01);g.gain.exponentialRampToValueAtTime(.001,t+dur);
  s.connect(f);f.connect(g);g.connect(SND.master);s.start(t,Math.random()*1.5);s.stop(t+dur+.05);}
function sTone(dur,f0,f1,vol,type,delay){if(!SND.ctx)return;const c=SND.ctx,t=c.currentTime+(delay||0);const o=c.createOscillator(),g=c.createGain();o.type=type||'sine';
  o.frequency.setValueAtTime(f0,t);o.frequency.exponentialRampToValueAtTime(Math.max(1,f1),t+dur);g.gain.setValueAtTime(vol,t);g.gain.exponentialRampToValueAtTime(.001,t+dur);o.connect(g);g.connect(SND.master);o.start(t);o.stop(t+dur+.05);}

/* ---------- continuous engines: truck, chainsaw, chipper ---------- */
function makeEngine(kind){if(!SND.ctx)return null;const c=SND.ctx;const out=c.createGain();out.gain.value=0;out.connect(SND.master);
  const o1=c.createOscillator(),o2=c.createOscillator();o1.type='sawtooth';o2.type='square';
  const ws=c.createWaveShaper();ws.curve=SND.curve;const lp=c.createBiquadFilter();lp.type='lowpass';
  const g1=c.createGain(),g2=c.createGain();g1.gain.value=.5;g2.gain.value=.25;o1.connect(g1);o2.connect(g2);g1.connect(ws);g2.connect(ws);ws.connect(lp);lp.connect(out);
  // grit (cutting / chipping / gravel)
  const n=noiseSrc(),nf=c.createBiquadFilter(),ng=c.createGain();nf.type='bandpass';nf.Q.value=.8;ng.gain.value=0;n.connect(nf);nf.connect(ng);ng.connect(out);
  // amplitude wobble for a two-stroke burble
  const lfo=c.createOscillator(),lg=c.createGain();lfo.frequency.value=kind==='saw'?22:9;lg.gain.value=.25;const am=c.createGain();am.gain.value=1;lfo.connect(lg);lg.connect(am.gain);
  lp.disconnect();lp.connect(am);am.connect(out);
  o1.start();o2.start();n.start();lfo.start();
  const E={kind,out,o1,o2,lp,ng,nf,lfo,vol:0,
    set(rpm,load,vol){const t=c.currentTime;let f;
      if(kind==='saw'){f=40+rpm*150;lp.frequency.setTargetAtTime(500+rpm*2600,t,.05);nf.frequency.setTargetAtTime(1800+rpm*1500,t,.05);lfo.frequency.setTargetAtTime(14+rpm*40,t,.05);}
      else if(kind==='chipper'){f=34+rpm*20;lp.frequency.setTargetAtTime(380+rpm*500,t,.1);nf.frequency.setTargetAtTime(900,t,.1);lfo.frequency.setTargetAtTime(8+rpm*6,t,.1);}
      else{f=30+rpm*55;lp.frequency.setTargetAtTime(260+rpm*420,t,.1);nf.frequency.setTargetAtTime(600,t,.1);lfo.frequency.setTargetAtTime(6+rpm*10,t,.1);}
      o1.frequency.setTargetAtTime(f,t,.04);o2.frequency.setTargetAtTime(f*2.01,t,.04);ng.gain.setTargetAtTime(load*(kind==='saw'?.35:.5),t,.05);out.gain.setTargetAtTime(vol,t,.08);E.vol=vol;},
    stop(){const t=c.currentTime;out.gain.setTargetAtTime(0,t,.15);setTimeout(()=>{try{o1.stop();o2.stop();n.stop();lfo.stop();}catch(e){}out.disconnect();},900);}};
  return E;}

/* ---------- named effects ---------- */
const SFX={
  pull(){sNoise(.35,900,1.2,.25,'bandpass');sTone(.3,180,90,.08,'sawtooth');},
  sputter(){sTone(.12,60,40,.2,'sawtooth');sNoise(.15,300,1,.2);sTone(.1,55,35,.15,'sawtooth',.15);},
  crack(){sNoise(.25,2200,1.5,.6,'bandpass');sNoise(.4,500,1,.5,'lowpass',.02);},
  creak(){if(!SND.ctx)return;const c=SND.ctx,t=c.currentTime;const o=c.createOscillator(),f=c.createBiquadFilter(),g=c.createGain();o.type='sawtooth';o.frequency.setValueAtTime(70,t);o.frequency.linearRampToValueAtTime(140,t+1.2);
    f.type='bandpass';f.frequency.value=900;f.Q.value=6;g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(.18,t+.3);g.gain.linearRampToValueAtTime(0,t+1.4);o.connect(f);f.connect(g);g.connect(SND.master);o.start(t);o.stop(t+1.5);},
  thud(v){const k=clamp(v/10,.15,1);sTone(.7,70,30,.9*k,'sine');sNoise(.5,250,.8,.7*k,'lowpass');sNoise(.35,1800,1,.25*k,'bandpass',.03);},
  crunch(){for(let i=0;i<5;i++)sNoise(.08,2500+Math.random()*2000,2,.25,'bandpass',i*.05);},
  glug(i){sNoise(.18,320+i*40,4,.35,'bandpass');sTone(.15,220,140,.08,'sine');},
  canCrush(){for(let i=0;i<6;i++)sNoise(.05,3000+Math.random()*3000,3,.2,'bandpass',i*.035);},
  clank(){sTone(.25,1900,1700,.12,'triangle');sTone(.18,2600,2400,.06,'sine');},
  door(){sNoise(.08,1500,2,.25,'bandpass');sTone(.06,400,300,.1,'square');},
  slam(){sTone(.35,90,45,.6,'sine');sNoise(.2,800,1,.4,'lowpass');},
  step(){sNoise(.07,500+Math.random()*300,1.4,.07,'bandpass');},
  pick(){sNoise(.12,700,1,.15,'bandpass');},
  drop(){sNoise(.15,300,1,.25,'lowpass');sTone(.15,120,60,.15,'sine');},
  blip(p){sTone(.06,p,p*.92,.05,'square');},
  cash(){sTone(.12,1800,1800,.15,'triangle');sTone(.5,2400,2400,.15,'triangle',.1);sNoise(.2,4000,2,.1,'bandpass',.05);},
  ding(){sTone(.4,880,880,.12,'sine');sTone(.5,1320,1320,.08,'sine',.08);},
};
