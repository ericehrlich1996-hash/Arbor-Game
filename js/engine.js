/* =====================================================================
   Arbor Simulator · engine.js
   Small math library, WebGL2 renderer and a mesh builder for low-poly models.
   Units: meters. Y is up.
   ===================================================================== */
'use strict';

/* ---------- vectors (plain arrays) ---------- */
const V = {
  add:(a,b)=>[a[0]+b[0],a[1]+b[1],a[2]+b[2]],
  sub:(a,b)=>[a[0]-b[0],a[1]-b[1],a[2]-b[2]],
  mul:(a,s)=>[a[0]*s,a[1]*s,a[2]*s],
  dot:(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2],
  cross:(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],
  len:a=>Math.hypot(a[0],a[1],a[2]),
  norm:a=>{const l=Math.hypot(a[0],a[1],a[2])||1;return [a[0]/l,a[1]/l,a[2]/l];},
  lerp:(a,b,t)=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t],
  dist:(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1],a[2]-b[2]),
};
const clamp=(x,a,b)=>x<a?a:x>b?b:x, lerp=(a,b,t)=>a+(b-a)*t, smooth=t=>t*t*(3-2*t);

/* ---------- quaternions [x,y,z,w] ---------- */
const Q = {
  ident:()=>[0,0,0,1],
  axis:(ax,an)=>{const s=Math.sin(an/2),n=V.norm(ax);return [n[0]*s,n[1]*s,n[2]*s,Math.cos(an/2)];},
  mul:(a,b)=>[a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]],
  rot:(q,v)=>{const [x,y,z,w]=q;const ix=w*v[0]+y*v[2]-z*v[1],iy=w*v[1]+z*v[0]-x*v[2],iz=w*v[2]+x*v[1]-y*v[0],iw=-x*v[0]-y*v[1]-z*v[2];
    return [ix*w+iw*-x+iy*-z-iz*-y,iy*w+iw*-y+iz*-x-ix*-z,iz*w+iw*-z+ix*-y-iy*-x];},
  conj:q=>[-q[0],-q[1],-q[2],q[3]],
  norm:q=>{const l=Math.hypot(q[0],q[1],q[2],q[3])||1;return [q[0]/l,q[1]/l,q[2]/l,q[3]/l];},
  // shortest rotation taking unit vector a to unit vector b
  between:(a,b)=>{const d=V.dot(a,b);if(d<-0.99999){let ax=V.cross([1,0,0],a);if(V.len(ax)<1e-4)ax=V.cross([0,0,1],a);return Q.axis(ax,Math.PI);}const c=V.cross(a,b);return Q.norm([c[0],c[1],c[2],1+d]);},
  toMat3:q=>{const [x,y,z,w]=q;return [1-2*(y*y+z*z),2*(x*y+z*w),2*(x*z-y*w), 2*(x*y-z*w),1-2*(x*x+z*z),2*(y*z+x*w), 2*(x*z+y*w),2*(y*z-x*w),1-2*(x*x+y*y)];},
  slerp:(a,b,t)=>{let d=a[0]*b[0]+a[1]*b[1]+a[2]*b[2]+a[3]*b[3];if(d<0){b=[-b[0],-b[1],-b[2],-b[3]];d=-d;}if(d>0.9995)return Q.norm([lerp(a[0],b[0],t),lerp(a[1],b[1],t),lerp(a[2],b[2],t),lerp(a[3],b[3],t)]);
    const th=Math.acos(d),s=Math.sin(th),wa=Math.sin((1-t)*th)/s,wb=Math.sin(t*th)/s;return [a[0]*wa+b[0]*wb,a[1]*wa+b[1]*wb,a[2]*wa+b[2]*wb,a[3]*wa+b[3]*wb];},
};

/* ---------- 4x4 matrices (column-major Float32Array) ---------- */
const M = {
  ident:()=>{const m=new Float32Array(16);m[0]=m[5]=m[10]=m[15]=1;return m;},
  mul:(a,b)=>{const o=new Float32Array(16);for(let c=0;c<4;c++)for(let r=0;r<4;r++){let s=0;for(let k=0;k<4;k++)s+=a[k*4+r]*b[c*4+k];o[c*4+r]=s;}return o;},
  T:(x,y,z)=>{const m=M.ident();m[12]=x;m[13]=y;m[14]=z;return m;},
  S:(x,y,z)=>{const m=M.ident();m[0]=x;m[5]=y==null?x:y;m[10]=z==null?x:z;return m;},
  Rx:a=>{const m=M.ident(),c=Math.cos(a),s=Math.sin(a);m[5]=c;m[6]=s;m[9]=-s;m[10]=c;return m;},
  Ry:a=>{const m=M.ident(),c=Math.cos(a),s=Math.sin(a);m[0]=c;m[2]=-s;m[8]=s;m[10]=c;return m;},
  Rz:a=>{const m=M.ident(),c=Math.cos(a),s=Math.sin(a);m[0]=c;m[1]=s;m[4]=-s;m[5]=c;return m;},
  // rotation from quaternion + translation
  QT:(q,p)=>{const r=Q.toMat3(q),m=M.ident();m[0]=r[0];m[1]=r[1];m[2]=r[2];m[4]=r[3];m[5]=r[4];m[6]=r[5];m[8]=r[6];m[9]=r[7];m[10]=r[8];if(p){m[12]=p[0];m[13]=p[1];m[14]=p[2];}return m;},
  persp:(fovy,asp,n,f)=>{const t=1/Math.tan(fovy/2),m=new Float32Array(16);m[0]=t/asp;m[5]=t;m[10]=(f+n)/(n-f);m[11]=-1;m[14]=2*f*n/(n-f);return m;},
  // camera looking from eye with yaw (about Y, 0 = -Z forward) and pitch
  view:(eye,yaw,pitch,roll)=>M.mul(M.mul(M.Rz(-(roll||0)),M.mul(M.Rx(-pitch),M.Ry(-yaw))),M.T(-eye[0],-eye[1],-eye[2])),
  apply:(m,p)=>[m[0]*p[0]+m[4]*p[1]+m[8]*p[2]+m[12],m[1]*p[0]+m[5]*p[1]+m[9]*p[2]+m[13],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]+m[14]],
  applyDir:(m,p)=>[m[0]*p[0]+m[4]*p[1]+m[8]*p[2],m[1]*p[0]+m[5]*p[1]+m[9]*p[2],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]],
};
// forward vector for a yaw/pitch camera
const fwdOf=(yaw,pitch)=>[-Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),-Math.cos(yaw)*Math.cos(pitch)];

/* ---------- seeded random ---------- */
function RNG(seed){let s=(seed>>>0)||1;const f=()=>{s^=s<<13;s>>>=0;s^=s>>17;s^=s<<5;s>>>=0;return s/4294967296;};
  f.range=(a,b)=>a+(b-a)*f();f.int=(a,b)=>Math.floor(a+(b-a+1)*f());f.pick=arr=>arr[Math.floor(f()*arr.length)];return f;}
// smooth value noise
function noise2(seed){const h=(x,y)=>{let n=(x*374761393+y*668265263+seed*2246822519)|0;n=(n^(n>>>13))*1274126177|0;return ((n^(n>>>16))>>>0)/4294967296;};
  return (x,y)=>{const xi=Math.floor(x),yi=Math.floor(y),fx=smooth(x-xi),fy=smooth(y-yi);
    return lerp(lerp(h(xi,yi),h(xi+1,yi),fx),lerp(h(xi,yi+1),h(xi+1,yi+1),fx),fy);};}

/* ---------- colors ---------- */
const hex=h=>{const n=parseInt(h.replace('#',''),16);return [(n>>16&255)/255,(n>>8&255)/255,(n&255)/255];};
const shade=(c,f)=>[c[0]*f,c[1]*f,c[2]*f];
const mixc=(a,b,t)=>[lerp(a[0],b[0],t),lerp(a[1],b[1],t),lerp(a[2],b[2],t)];

/* =====================================================================
   Mesh builder: primitives are built in local space and transformed by
   the current matrix (push/pop like an old-school matrix stack).
   ===================================================================== */
class MeshB {
  constructor(){this.p=[];this.n=[];this.c=[];this.i=[];this.m=M.ident();this.stack=[];}
  push(m){this.stack.push(this.m);if(m)this.m=M.mul(this.m,m);return this;}
  pop(){this.m=this.stack.pop();return this;}
  tf(m){this.m=M.mul(this.m,m);return this;}
  v(p,n,c){const q=M.apply(this.m,p),d=V.norm(M.applyDir(this.m,n));this.p.push(q[0],q[1],q[2]);this.n.push(d[0],d[1],d[2]);this.c.push(c[0],c[1],c[2]);return this.p.length/3-1;}
  tri(a,b,c){this.i.push(a,b,c);}
  quad(a,b,c,d){this.i.push(a,b,c,a,c,d);}
  // flat quad from 4 corners with automatic normal
  face(P,col){const n=V.norm(V.cross(V.sub(P[1],P[0]),V.sub(P[2],P[0])));const a=this.v(P[0],n,col),b=this.v(P[1],n,col),c=this.v(P[2],n,col),d=this.v(P[3],n,col);this.quad(a,b,c,d);}
  // axis-aligned box centred at (x,y,z)
  box(x,y,z,sx,sy,sz,col,cols){const hx=sx/2,hy=sy/2,hz=sz/2;const C=(i)=>cols?cols[i]:col;
    const F=[[[1,0,0],[[x+hx,y-hy,z+hz],[x+hx,y-hy,z-hz],[x+hx,y+hy,z-hz],[x+hx,y+hy,z+hz]]],[[-1,0,0],[[x-hx,y-hy,z-hz],[x-hx,y-hy,z+hz],[x-hx,y+hy,z+hz],[x-hx,y+hy,z-hz]]],
      [[0,1,0],[[x-hx,y+hy,z+hz],[x+hx,y+hy,z+hz],[x+hx,y+hy,z-hz],[x-hx,y+hy,z-hz]]],[[0,-1,0],[[x-hx,y-hy,z-hz],[x+hx,y-hy,z-hz],[x+hx,y-hy,z+hz],[x-hx,y-hy,z+hz]]],
      [[0,0,1],[[x-hx,y-hy,z+hz],[x+hx,y-hy,z+hz],[x+hx,y+hy,z+hz],[x-hx,y+hy,z+hz]]],[[0,0,-1],[[x+hx,y-hy,z-hz],[x-hx,y-hy,z-hz],[x-hx,y+hy,z-hz],[x+hx,y+hy,z-hz]]]];
    F.forEach(([n,P],k)=>{const col=shade(C(k),1);const a=this.v(P[0],n,col),b=this.v(P[1],n,col),c=this.v(P[2],n,col),d=this.v(P[3],n,col);this.quad(a,b,c,d);});return this;}
  // cylinder / cone along +Y from y0 to y1 (smooth sides); cap flags
  cyl(x,y0,z,r0,r1,h,col,seg=12,caps=true,colTop){const y1=y0+h,ring=[];const sl=(r0-r1)/h;
    for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2,cx=Math.cos(a),cz=Math.sin(a),n=V.norm([cx,sl,cz]);
      ring.push([this.v([x+cx*r0,y0,z+cz*r0],n,col),this.v([x+cx*r1,y1,z+cz*r1],n,col)]);}
    for(let s=0;s<seg;s++)this.quad(ring[s][0],ring[s+1][0],ring[s+1][1],ring[s][1]);
    if(caps){const ct=colTop||col;const t=this.v([x,y1,z],[0,1,0],ct),b=this.v([x,y0,z],[0,-1,0],col);const T=[],B=[];
      for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;T.push(this.v([x+Math.cos(a)*r1,y1,z+Math.sin(a)*r1],[0,1,0],ct));B.push(this.v([x+Math.cos(a)*r0,y0,z+Math.sin(a)*r0],[0,-1,0],col));}
      for(let s=0;s<seg;s++){this.tri(t,T[s+1],T[s]);this.tri(b,B[s],B[s+1]);}}
    return this;}
  // tapered tube between two points (any orientation)
  tube(a,b,r0,r1,col,seg=8,caps=false,colEnd){const d=V.sub(b,a),L=V.len(d);if(L<1e-6)return this;const q=Q.between([0,1,0],V.norm(d));
    this.push(M.QT(q,a));this.cyl(0,0,0,r0,r1,L,col,seg,caps,colEnd);this.pop();return this;}
  sphere(x,y,z,rx,ry,rz,col,seg=10,ring=7,colFn){const idx=[];for(let j=0;j<=ring;j++){const v=j/ring*Math.PI,row=[];for(let s=0;s<=seg;s++){const u=s/seg*Math.PI*2;
      const n=[Math.sin(v)*Math.cos(u),Math.cos(v),Math.sin(v)*Math.sin(u)];row.push(this.v([x+n[0]*rx,y+n[1]*ry,z+n[2]*rz],V.norm([n[0]/rx,n[1]/ry,n[2]/rz]),colFn?colFn(n):col));}idx.push(row);}
    for(let j=0;j<ring;j++)for(let s=0;s<seg;s++)this.quad(idx[j][s],idx[j][s+1],idx[j+1][s+1],idx[j+1][s]);return this;}
  // flat-shaded low-poly blob (icosphere-ish) for foliage
  blob(x,y,z,r,col,rng,sq=1){const t=(1+Math.sqrt(5))/2;const P=[[-1,t,0],[1,t,0],[-1,-t,0],[1,-t,0],[0,-1,t],[0,1,t],[0,-1,-t],[0,1,-t],[t,0,-1],[t,0,1],[-t,0,-1],[-t,0,1]].map(p=>{const n=V.norm(p),j=rng?rng.range(.82,1.12):1;return [x+n[0]*r*j,y+n[1]*r*j*sq,z+n[2]*r*j];});
    const F=[[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]];
    for(const f of F){const a=P[f[0]],b=P[f[1]],c=P[f[2]];const n=V.norm(V.cross(V.sub(b,a),V.sub(c,a)));const cc=rng?shade(col,rng.range(.85,1.12)):col;const i0=this.v(a,n,cc),i1=this.v(b,n,cc),i2=this.v(c,n,cc);this.tri(i0,i1,i2);}return this;}
  // flat disk facing +Y
  disk(x,y,z,r,col,seg=16){const c=this.v([x,y,z],[0,1,0],col),R=[];for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;R.push(this.v([x+Math.cos(a)*r,y,z+Math.sin(a)*r],[0,1,0],col));}for(let s=0;s<seg;s++)this.tri(c,R[s+1],R[s]);return this;}
  // prism from a 2D polygon (in XY plane) extruded along Z from z0 to z1
  prism(pts,z0,z1,col,colSide){const n=pts.length,F=[],B=[];for(const [x,y] of pts){F.push(this.v([x,y,z1],[0,0,1],col));}for(const [x,y] of pts){B.push(this.v([x,y,z0],[0,0,-1],col));}
    for(let k=1;k<n-1;k++){this.tri(F[0],F[k],F[k+1]);this.tri(B[0],B[k+1],B[k]);}
    for(let k=0;k<n;k++){const a=pts[k],b=pts[(k+1)%n];this.face([[a[0],a[1],z0],[b[0],b[1],z0],[b[0],b[1],z1],[a[0],a[1],z1]].reverse(),colSide||col);}return this;}
  count(){return this.i.length;}
}

/* =====================================================================
   Renderer (WebGL2). Every drawable is a mesh + a model matrix + tint.
   ===================================================================== */
const VS=`#version 300 es
in vec3 p;in vec3 n;in vec3 c;uniform mat4 VP,Mo;uniform vec3 cam;out vec3 vN,vC,vW;
void main(){vec4 w=Mo*vec4(p,1.);vW=w.xyz;vN=mat3(Mo)*n;vC=c;gl_Position=VP*w;}`;
const FS=`#version 300 es
precision highp float;in vec3 vN,vC,vW;uniform vec3 sun,sunC,skyC,gndC,fogC,cam;uniform vec2 fogR;uniform vec4 tint;uniform float emis;out vec4 o;
void main(){vec3 N=normalize(vN);if(!gl_FrontFacing)N=-N;float d=max(dot(N,sun),0.);float h=N.y*.5+.5;
 vec3 col=vC*tint.rgb;vec3 lit=col*(sunC*d+mix(gndC,skyC,h))+col*emis;
 float f=clamp((distance(vW,cam)-fogR.x)/(fogR.y-fogR.x),0.,1.);o=vec4(mix(lit,fogC,f*f),tint.a);}`;
class Renderer{
  constructor(cv){this.cv=cv;const gl=cv.getContext('webgl2',{antialias:true,alpha:false});if(!gl)throw new Error('WebGL2 is not available');this.gl=gl;
    const sh=(t,s)=>{const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);if(!gl.getShaderParameter(o,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(o));return o;};
    const pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,VS));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,FS));gl.bindAttribLocation(pr,0,'p');gl.bindAttribLocation(pr,1,'n');gl.bindAttribLocation(pr,2,'c');gl.linkProgram(pr);
    if(!gl.getProgramParameter(pr,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(pr));this.pr=pr;gl.useProgram(pr);
    this.u={};for(const k of ['VP','Mo','cam','sun','sunC','skyC','gndC','fogC','fogR','tint','emis'])this.u[k]=gl.getUniformLocation(pr,k);
    gl.enable(gl.DEPTH_TEST);gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);gl.disable(gl.CULL_FACE);
    this.env={sun:V.norm([.45,.8,.35]),sunC:[1.05,.98,.88],skyC:[.52,.6,.68],gndC:[.3,.29,.22],fogC:[.72,.8,.86],fogR:[60,260]};}
  upload(mb){const gl=this.gl;if(!mb.i.length)return null;const vao=gl.createVertexArray();gl.bindVertexArray(vao);const bufs=[];
    const att=(i,arr)=>{const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(arr),gl.STATIC_DRAW);gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,3,gl.FLOAT,false,0,0);bufs.push(b);};
    att(0,mb.p);att(1,mb.n);att(2,mb.c);const ib=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,ib);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint32Array(mb.i),gl.STATIC_DRAW);bufs.push(ib);
    gl.bindVertexArray(null);return {vao,bufs,n:mb.i.length};}
  free(m){if(!m)return;const gl=this.gl;m.bufs.forEach(b=>gl.deleteBuffer(b));gl.deleteVertexArray(m.vao);}
  resize(){const d=Math.min(window.devicePixelRatio||1,2),w=Math.round(this.cv.clientWidth*d),h=Math.round(this.cv.clientHeight*d);if(this.cv.width!==w||this.cv.height!==h){this.cv.width=w;this.cv.height=h;}this.gl.viewport(0,0,w,h);}
  begin(VP,cam,clear){const gl=this.gl,e=this.env,u=this.u;this.VP=VP;
    if(clear){gl.clearColor(e.fogC[0],e.fogC[1],e.fogC[2],1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);}
    gl.uniformMatrix4fv(u.VP,false,VP);gl.uniform3fv(u.cam,cam);gl.uniform3fv(u.sun,e.sun);gl.uniform3fv(u.sunC,e.sunC);gl.uniform3fv(u.skyC,e.skyC);gl.uniform3fv(u.gndC,e.gndC);gl.uniform3fv(u.fogC,e.fogC);gl.uniform2fv(u.fogR,e.fogR);
    gl.uniform4f(u.tint,1,1,1,1);gl.uniform1f(u.emis,0);}
  draw(mesh,Mo,tint,emis){if(!mesh)return;const gl=this.gl;gl.uniformMatrix4fv(this.u.Mo,false,Mo||M.ident());if(tint)gl.uniform4fv(this.u.tint,tint);else gl.uniform4f(this.u.tint,1,1,1,1);gl.uniform1f(this.u.emis,emis||0);
    gl.bindVertexArray(mesh.vao);gl.drawElements(gl.TRIANGLES,mesh.n,gl.UNSIGNED_INT,0);}
  clearDepth(){this.gl.clear(this.gl.DEPTH_BUFFER_BIT);}
}
