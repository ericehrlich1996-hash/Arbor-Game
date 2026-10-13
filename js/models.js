/* =====================================================================
   Arbor Simulator · models.js
   Low-poly models built in code.
   Truck frame: x right, y up, z forward; origin on the ground midway between axles.
   ===================================================================== */
'use strict';

const TRUCK_PAINT=[['#8b2a1f','#ece6d8'],['#2d4a7a','#e9e6dc'],['#6a4a2a','#d8c49a'],['#33503a','#e6e2d4'],['#a8742a','#efe7d2']];
const TRUCK={wheelR:.4,frontAxle:1.62,rearAxle:-1.58,track:.82,hitch:[0,.5,-2.95],eye:[-.40,1.50,-.20]};

function buildTruck(R){const mb=new MeshB();const [c1,c2]=R.pick(TRUCK_PAINT).map(hex);
  const chrome=hex('#c9ccd0'),black=hex('#1c1d1f'),dark=hex('#2a2b2d'),glassF=hex('#1e2830'),vinyl=hex('#b89a6a'),dash=hex('#3a2e26'),rubber=hex('#151515');
  const W2=1.0;  // half width
  // ---------- front clip ----------
  mb.box(0,1.04,1.62,2.0,.5,1.7,c1);                          // hood + fender mass
  mb.box(0,1.31,1.62,1.94,.05,1.66,shade(c1,1.05));            // flat hood top
  for(const sx of [-1,1]){mb.box(sx*.98,.98,1.62,.06,.36,1.72,c2);}  // white side band
  // wheel arch shadows (dark boxes inset)
  for(const sx of [-1,1])for(const z of [TRUCK.frontAxle,TRUCK.rearAxle])mb.box(sx*.97,.62,z,.1,.4,1.0,black);
  // grille + quad headlights
  mb.box(0,1.0,2.48,1.86,.5,.06,chrome);mb.box(0,1.0,2.505,1.5,.36,.04,dark);
  for(let k=0;k<7;k++)mb.box(0,.86+k*.045,2.53,1.46,.012,.02,shade(chrome,.75));
  for(const sx of [-1,1])for(const yy of [1.06,.94]){mb.box(sx*.78,yy,2.52,.26,.1,.04,hex('#f4f0d8'));mb.box(sx*.78,yy,2.505,.3,.13,.03,chrome);}
  mb.box(0,1.1,2.535,.22,.08,.02,shade(c2,.9));                // emblem plate (blank)
  // chrome bumper
  mb.box(0,.62,2.62,2.06,.24,.16,chrome);mb.box(0,.52,2.58,1.7,.06,.1,dark);
  mb.box(0,.9,2.0,1.5,.8,1.0,black);                          // engine bay fill under hood
  // ---------- cab ----------
  const cz0=-.68,cz1=.78;
  mb.box(W2-.03,.98,(cz0+cz1)/2,.06,.66,cz1-cz0,c1);mb.box(W2-.02,.98,(cz0+cz1)/2,.03,.3,cz1-cz0-.06,c2);   // passenger door (driver door is its own mesh)
  mb.box(0,.98,cz0+.03,2.0,.66,.06,c1);                         // cab back wall (lower)
  mb.box(0,.68,(cz0+cz1)/2,2.0,.08,cz1-cz0,black);             // floor
  // greenhouse: pillars + roof (open glass so the interior is visible)
  const yb=1.31,yt=1.95;
  mb.box(0,yt,-.08,1.96,.07,1.2,c2);                            // roof (white top, classic two-tone)
  for(const sx of [-1,1]){mb.tube([sx*.95,yb,.8],[sx*.93,yt-.02,.5],.035,.035,c2,5);  // A pillar
    mb.box(sx*.96,(yb+yt)/2,cz0+.05,.08,yt-yb,.1,c2);                                  // B pillar
    if(sx>0)mb.box(sx*.97,yb+.02,.06,.05,.05,1.45,c1);}                                 // window sill
  mb.box(0,(yb+yt)/2,cz0+.03,1.9,yt-yb,.05,c2);mb.box(0,1.63,cz0+.01,1.0,.36,.03,glassF);   // back wall + rear window
  mb.box(0,yt-.04,.52,1.9,.06,.08,c2);mb.box(0,yb+.02,.8,1.9,.05,.08,c2);              // windshield header + cowl
  // drip rails + mirrors
  for(const sx of [-1,1]){mb.box(sx*1.0,yt-.02,-.08,.03,.03,1.2,chrome);mb.tube([sx*.98,1.38,.66],[sx*1.18,1.48,.62],.012,.012,chrome,4);mb.box(sx*1.2,1.52,.62,.05,.24,.16,chrome);mb.box(sx*1.2,1.52,.6,.04,.2,.12,hex('#9ab0bf'));}
  // ---------- interior ----------
  mb.box(0,1.06,.66,1.9,.18,.26,dash);mb.box(0,1.16,.6,1.88,.04,.34,shade(dash,1.15));   // dashboard + pad
  mb.box(-.4,1.13,.5,.5,.16,.08,shade(dash,.8));                                        // instrument hood
  for(const gx of [-.52,-.28]){mb.push(M.T(gx,1.1,.455));mb.tf(M.Rx(Math.PI/2));mb.cyl(0,0,0,.07,.07,.01,hex('#e8e2cc'),14,true,hex('#e8e2cc'));mb.pop();
    mb.push(M.T(gx,1.1,.45));mb.tf(M.Rz(gx<-.4?-.6:.3));mb.box(0,.03,0,.006,.06,.004,hex('#c0392b'));mb.pop();}
  mb.box(.35,1.03,.53,.45,.08,.02,hex('#6a6f75'));                                       // radio
  // steering wheel (ring of short tubes) + column
  {const cx=-.4,cy=1.12,cz=.38,r=.19,tilt=-.42;mb.push(M.mul(M.T(cx,cy,cz),M.Rx(tilt)));
    for(let k=0;k<20;k++){const a0=k/20*Math.PI*2,a1=(k+1)/20*Math.PI*2;mb.tube([Math.cos(a0)*r,Math.sin(a0)*r,0],[Math.cos(a1)*r,Math.sin(a1)*r,0],.016,.016,rubber,6);}
    mb.tube([0,0,0],[-r*.95,-.03,0],.014,.014,rubber,5);mb.tube([0,0,0],[r*.95,-.03,0],.014,.014,rubber,5);mb.cyl(0,-.02,0,.05,.05,.04,dark,8);mb.pop();
    mb.tube([cx,cy-.02,cz+.02],[cx,1.0,.62],.03,.035,dark,6);mb.tube([cx+.06,1.06,.44],[cx+.2,1.0,.42],.008,.008,chrome,4);}   // column + shifter
  // bench seat
  mb.box(0,.72,-.3,1.84,.16,.5,vinyl);mb.box(0,1.05,-.56,1.84,.62,.14,shade(vinyl,.95));
  for(let k=0;k<6;k++)mb.box(-.75+k*.3,1.05,-.485,.02,.56,.01,shade(vinyl,.82));
  mb.box(0,yt-.06,-.08,1.88,.02,1.18,hex('#9a8f80'));                                    // headliner
  mb.box(0,1.86,.5,.06,.08,.03,hex('#2a2d30'));mb.box(0,1.79,.48,.38,.13,.03,hex('#2a2d30'));                // rear-view mirror (the glass is drawn live)
  mb.box(.94,.98,.04,.03,.5,1.3,shade(vinyl,.8));                                         // passenger door card
  // ---------- bed ----------
  const bz0=-2.62,bz1=cz0-.08;
  for(const sx of [-1,1]){mb.box(sx*.97,1.0,(bz0+bz1)/2,.07,.62,bz1-bz0,c1);mb.box(sx*.98,.98,(bz0+bz1)/2,.03,.3,bz1-bz0,c2);mb.box(sx*.97,1.33,(bz0+bz1)/2,.1,.04,bz1-bz0,shade(c1,1.1));}
  mb.box(0,.74,(bz0+bz1)/2,1.9,.06,bz1-bz0,hex('#3a3632'));                               // bed floor
  for(let k=0;k<7;k++)mb.box(-.75+k*.25,.78,(bz0+bz1)/2,.04,.02,bz1-bz0,hex('#4a4540'));
  mb.box(0,1.0,bz1+.02,1.9,.62,.05,c1);const tg=new MeshB();tg.box(0,1.0,bz0,2.0,.62,.07,c1);tg.box(0,.98,bz0-.03,1.6,.08,.02,chrome);   // front wall; the tailgate is its own see-through mesh
  for(const sx of [-1,1]){mb.box(sx*.92,.92,bz0-.04,.14,.24,.03,hex('#b8281e'));}      // tail lights
  mb.box(0,.56,bz0-.14,2.0,.18,.14,chrome);                                              // rear bumper
  mb.box(0,.5,bz0-.32,.1,.06,.36,dark);mb.sphere(0,.58,TRUCK.hitch[2],.05,.05,.05,chrome,8,6);   // hitch + ball
  // chassis
  mb.box(0,.5,0,1.1,.18,4.6,black);
  return {mesh:mb,c1,c2,tailgate:tg};}
function buildWheel(){const mb=new MeshB();mb.push(M.Rz(Math.PI/2));
  mb.cyl(0,-.14,0,.4,.4,.28,hex('#1a1a1a'),18,true,hex('#1a1a1a'));
  mb.cyl(0,.141,0,.24,.24,.005,hex('#d8dadc'),14,true);mb.cyl(0,.146,0,.1,.1,.01,hex('#9aa0a6'),10,true);
  for(let k=0;k<6;k++){const a=k/6*Math.PI*2;mb.box(Math.cos(a)*.17,.149,Math.sin(a)*.17,.03,.01,.03,hex('#5a5f64'));}
  mb.pop();return mb;}

/* ---------- wood chipper (towed) ---------- */
// frame: origin at the tongue coupler; trailer body extends toward −Z; the infeed faces −Z.
const CHIP={axle:-2.3,hopper:[0,1.0,-3.75],len:2.3};
function buildChipper(){const mb=new MeshB();const body=hex('#d9861c'),dk=hex('#262729'),steel=hex('#6a6e72'),yel=hex('#e8c23a');
  mb.tube([0,.5,0],[-.5,.42,-1.3],.04,.04,dk,6);mb.tube([0,.5,0],[.5,.42,-1.3],.04,.04,dk,6);mb.box(0,.5,-.05,.12,.08,.2,dk);   // A-frame tongue
  mb.box(0,.45,-2.2,1.1,.12,2.0,dk);                                            // frame
  mb.box(0,.75,-.4,.12,.5,.12,dk);mb.cyl(0,.25,-.4,.06,.06,.25,steel,8);         // jack stand
  mb.box(0,1.0,-1.55,1.1,.9,1.0,body);mb.box(0,1.48,-1.55,1.0,.08,.9,shade(body,1.1));   // engine hood
  for(let k=0;k<6;k++)mb.box(.56,1.0,-1.25-k*.1,.02,.5,.04,dk);                  // vents
  mb.cyl(-.3,1.52,-1.3,.05,.05,.35,dk,8);                                       // exhaust
  mb.box(0,1.05,-2.45,1.0,1.1,.9,shade(body,.9));                               // drum housing
  mb.cyl(0,1.05,-2.45,.48,.48,.0,body);
  // infeed hopper (flared chute facing −Z) + feed tray
  const hz=-2.9,hz2=-3.9;mb.box(0,1.0,hz-.05,.8,.7,.1,steel);
  const fl=(a,b,c,d,col)=>mb.face([a,b,c,d],col);
  fl([-.4,.65,hz],[.4,.65,hz],[.62,.55,hz2],[-.62,.55,hz2],steel);            // floor
  fl([-.4,1.35,hz],[-.62,1.5,hz2],[.62,1.5,hz2],[.4,1.35,hz],shade(steel,.9));    // top
  fl([-.4,.65,hz],[-.62,.55,hz2],[-.62,1.5,hz2],[-.4,1.35,hz],shade(steel,1.1)); // sides
  fl([.4,.65,hz],[.4,1.35,hz],[.62,1.5,hz2],[.62,.55,hz2],shade(steel,1.1));
  mb.box(0,1.0,hz+.02,.7,.6,.04,hex('#111214'));                                // throat
  mb.box(0,1.56,hz2+.06,1.3,.05,.06,yel);mb.box(-.66,1.0,hz2+.06,.05,.95,.06,yel);mb.box(.66,1.0,hz2+.06,.05,.95,.06,yel);  // feed-control bar
  // discharge chute: rises from the drum and curves forward over the truck bed
  let p=[0,1.55,-2.45];for(let k=0;k<6;k++){const t=(k+1)/6;const q=[0,1.55+Math.sin(t*1.4)*.95,-2.45+t*1.5];mb.tube(p,q,.15,.15,body,8);p=q;}
  mb.box(0,p[1],p[2]+.08,.32,.2,.16,shade(body,.85));
  // fenders
  for(const sx of [-1,1]){mb.box(sx*.78,.82,CHIP.axle,.3,.06,.95,dk);}
  // tool rack on the left side: two brackets, a cradle rail and a lip
  for(const z of [-1.62,-2.5]){mb.box(-.6,.78,z,.08,.42,.05,dk);mb.box(-.7,.6,z,.2,.05,.05,dk);}
  mb.box(-.78,.62,-2.06,.04,.08,1.0,steel);mb.box(-.66,.62,-2.06,.04,.04,1.0,steel);mb.box(-.79,.69,-2.06,.02,.08,1.0,yel);
  // warning decals
  mb.box(.551,1.15,-2.45,.01,.18,.5,yel);mb.box(-.551,1.15,-2.45,.01,.18,.5,yel);
  return mb;}

/* ---------- the old man (separate parts for posing) ---------- */
function buildOldMan(){const P={};const skin=hex('#e0b090'),denim=hex('#3d5a80'),shirt=hex('#b0302a'),dkC=hex('#262626'),boot=hex('#4a3626'),white=hex('#efede6'),cap=hex('#3e6a3a');
  // torso (origin at hips)
  let mb=new MeshB();mb.box(0,.28,0,.42,.56,.25,shirt);for(let k=0;k<5;k++)mb.box(0,.04+k*.12,0,.425,.025,.255,dkC);for(let k=0;k<4;k++)mb.box(-.15+k*.1,.28,0,.025,.56,.255,shade(shirt,.6));
  mb.box(0,.17,-.13,.32,.36,.02,denim);mb.box(0,-.02,0,.43,.16,.26,denim);   // bib + waist of overalls
  for(const sx of [-1,1])mb.box(sx*.11,.4,-.13,.05,.3,.02,denim);            // straps
  mb.sphere(0,.38,.0,.24,.26,.15,shirt,8,5);                                 // shoulders/belly roundness
  P.torso=mb;
  // head (origin at neck)
  mb=new MeshB();mb.cyl(0,0,0,.06,.06,.08,skin,8);mb.sphere(0,.16,0,.11,.13,.115,skin,10,7);
  mb.sphere(0,.08,-.06,.1,.1,.08,white,8,6);mb.sphere(0,.12,-.11,.09,.035,.04,white,8,4);                // beard + moustache
  mb.sphere(0,.16,-.12,.025,.03,.03,shade(skin,.9),6,4);                                                // nose
  for(const sx of [-1,1]){mb.sphere(sx*.045,.19,-.1,.016,.012,.01,dkC,6,4);mb.box(sx*.045,.215,-.105,.04,.012,.01,white);}   // eyes + bushy brows
  mb.box(0,.19,-.112,.15,.008,.008,hex('#8a8a8a'));for(const sx of [-1,1]){mb.cyl(sx*.045,.19,-.113,.028,.028,.0,hex('#8a8a8a'),10,false);}   // glasses
  mb.sphere(0,.25,0,.12,.07,.12,cap,10,5);mb.box(0,.235,-.14,.18,.02,.12,cap);mb.box(0,.29,0,.2,.07,.2,cap);mb.box(0,.29,-.101,.12,.06,.002,white);   // trucker cap
  for(let k=0;k<7;k++){const a=-1.2+k*.4;mb.tube([Math.sin(a)*.1,.2,Math.cos(a)*.1],[Math.sin(a)*.18,.22+(k%2)*.04,Math.cos(a)*.17],.02,.004,white,4);}   // wild hair
  P.head=mb;
  // arm (origin at shoulder, hangs down −Y): upper + forearm built separately for elbow bend
  mb=new MeshB();mb.tube([0,0,0],[0,-.3,0],.055,.05,shirt,7);for(let k=0;k<3;k++)mb.cyl(0,-.08-k*.08,0,.057,.057,.02,dkC,7,false);P.upper=mb;
  mb=new MeshB();mb.tube([0,0,0],[0,-.26,0],.048,.04,shirt,7);mb.sphere(0,-.31,0,.05,.06,.035,skin,7,5);P.fore=mb;
  // leg (origin at hip)
  mb=new MeshB();mb.tube([0,0,0],[0,-.84,0],.08,.07,denim,8);mb.box(0,-.86,-.04,.12,.09,.26,boot);P.leg=mb;
  // cane
  mb=new MeshB();mb.tube([0,0,0],[0,-.9,0],.015,.015,hex('#6a4a2a'),5);mb.tube([0,0,0],[0,.04,-.1],.015,.015,hex('#6a4a2a'),5);P.cane=mb;
  return P;}

/* ---------- chainsaw view model (camera space: −Z forward) ---------- */
// The bar tip sits at about (0,−.02,−.62) in saw space; the saw origin is the rear handle.
function buildChainsaw(){const mb=new MeshB();const orange=hex('#e8661c'),white=hex('#ecebe6'),dk=hex('#232426'),steel=hex('#8a8e92');
  mb.box(0,.05,-.16,.11,.15,.26,orange);mb.box(0,.135,-.16,.105,.03,.22,white);   // body + top cover
  mb.box(.06,.04,-.12,.02,.1,.14,dk);                                           // starter side
  mb.box(-.062,.05,-.2,.02,.08,.12,steel);                                       // muffler
  mb.box(0,.07,-.02,.05,.06,.06,dk);mb.tube([0,.02,.02],[0,.02,.09],.022,.022,dk,6);mb.tube([0,.02,.09],[0,.09,.07],.02,.02,dk,6);mb.tube([0,.09,.07],[0,.1,-.01],.02,.02,dk,6);  // rear handle loop
  mb.tube([-.07,-.02,-.24],[-.07,.17,-.24],.015,.015,dk,6);mb.tube([-.07,.17,-.24],[.06,.17,-.2],.015,.015,dk,6);mb.tube([.06,.17,-.2],[.06,.05,-.18],.015,.015,dk,6);   // front wrap handle
  mb.box(-.0,.19,-.27,.09,.07,.012,dk);                                          // chain brake / hand guard
  mb.box(.03,.13,-.05,.03,.025,.04,hex('#eeeeee'));                              // start switch
  mb.box(.06,.08,-.08,.025,.02,.03,dk);                                          // pull-cord grip
  // bar + chain
  mb.box(0,-.0,-.52,.012,.07,.62,steel);mb.box(0,.0,-.52,.016,.075,.6,dk);mb.box(0,0,-.52,.013,.055,.62,steel);
  mb.sphere(0,0,-.83,.012,.037,.02,steel,6,4);
  for(let k=0;k<26;k++){const z=-.24-k*.023;mb.box(0,.04,z,.016,.012,.012,dk);mb.box(0,-.04,z,.016,.012,.012,dk);}
  mb.box(0,-.0,-.22,.06,.09,.04,dk);                                              // clutch cover
  return mb;}
// work gloves + sleeves; side: +1 right, −1 left; hand at origin, arm reaching back toward the camera
function buildGlove(side){const mb=new MeshB();const glove=hex('#c9a46a'),cuff=hex('#9c7a44'),sleeve=hex('#5a6a3a');
  mb.sphere(0,0,0,.05,.045,.065,glove,8,6);for(let k=0;k<4;k++)mb.tube([-.03+k*.02,.02,-.04],[-.03+k*.02,-.035,-.06],.014,.012,shade(glove,.95),5);
  mb.tube([side*-.035,.0,.02],[side*-.05,-.03,-.04],.016,.014,glove,5);
  mb.tube([0,0,.04],[side*.06,-.12,.3],.05,.06,cuff,7);mb.tube([side*.06,-.12,.3],[side*.14,-.26,.62],.06,.075,sleeve,8);
  return mb;}
function buildCan(){const mb=new MeshB();const g=hex('#1d1f22'),lime=hex('#8be02c'),al=hex('#c8ccd0');
  mb.cyl(0,0,0,.033,.033,.16,g,14,true,al);mb.cyl(0,.03,0,.0335,.0335,.03,lime,14,false);mb.cyl(0,.1,0,.0335,.0335,.015,lime,14,false);
  for(let k=0;k<3;k++)mb.box(Math.cos(k*2.1)*.034,.075,Math.sin(k*2.1)*.034,.01,.05,.01,lime);
  mb.cyl(0,.16,0,.033,.026,.012,al,14,true);mb.box(.01,.174,0,.02,.003,.01,shade(al,.8));
  return mb;}
function buildRightHandCan(){const mb=new MeshB();const skin=hex('#e0b090'),sleeve=hex('#5a6a3a');
  // fingers wrapping the can (can axis along Y at origin)
  for(let k=0;k<4;k++){const y=.03+k*.032;mb.tube([.03,y,-.025],[-.01,y,-.045],.012,.011,skin,5);mb.tube([-.01,y,-.045],[-.04,y,-.02],.011,.01,skin,5);}
  mb.sphere(.035,.06,.0,.03,.06,.035,skin,7,5);mb.tube([.03,.1,.01],[.0,.13,-.03],.013,.012,skin,5);
  mb.sphere(.04,0,.01,.035,.03,.035,skin,7,5);
  return mb;}
// forearm for the drink animation: hangs down from the wrist so it never swings through the camera
function buildForearm(){const mb=new MeshB();const skin=hex('#e0b090'),sleeve=hex('#5a6a3a');
  mb.tube([.04,-.01,.02],[.1,-.22,.1],.038,.05,skin,7);mb.tube([.1,-.22,.1],[.18,-.6,.2],.06,.08,sleeve,8);for(let k=0;k<3;k++)mb.cyl(.1,-.25-k*.03,.1,.062,.062,.012,shade(sleeve,.8),8,false);return mb;}

/* ---------- gloved fist gripping a bar that runs along local X through the origin ---------- */
function buildFist(side){const mb=new MeshB();const glove=hex('#c9a46a'),gD=hex('#a8844c'),cuff=hex('#8a6a3a');
  // back of the hand sits over the bar, knuckles toward −Z, fingers curl down and under it
  mb.sphere(0,.028,.012,.042,.022,.036,glove,10,6);
  for(let k=0;k<4;k++){const x=-.033+k*.022;const a=[x,.03,-.022],b=[x,.004,-.03],c=[x,-.022,-.012],d=[x,-.018,.012];
    mb.tube(a,b,.0105,.0102,shade(glove,.97),6);mb.tube(b,c,.0102,.0098,glove,6);mb.tube(c,d,.0098,.009,shade(glove,.94),6);mb.sphere(x,.03,-.02,.012,.012,.012,gD,6,4);}
  mb.tube([side*.045,.02,.01],[side*.05,-.005,-.02],.012,.011,glove,6);mb.tube([side*.05,-.005,-.02],[side*.03,-.022,-.028],.011,.01,glove,6);   // thumb wraps the far side
  mb.tube([0,.026,.03],[0,.02,.07],.036,.04,cuff,9);                                                                                      // gauntlet cuff
  return mb;}
// a unit sleeve from (0,0,0) to (0,1,0); scaled per frame to run from the wrist toward the shoulder
function buildArm(){const mb=new MeshB();const sleeve=hex('#5a6a3a');mb.cyl(0,0,0,1,1.15,1,sleeve,10,false);for(let k=0;k<2;k++)mb.cyl(0,.12+k*.05,0,1.04,1.04,.02,shade(sleeve,.75),10,false);return mb;}
