(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const canvas = $('table');
  const ctx = canvas.getContext('2d', { alpha: false });
  const LOGICAL_WIDTH=1000, LOGICAL_HEIGHT=560;
  const PI = Math.PI, TWO_PI = PI * 2;
  const T = { L: 74, R: 926, U: 73, D: 487, head: 286, r: 11.1 };
  const pockets = [
    {x:T.L,y:T.U,r:24}, {x:500,y:T.U,r:23}, {x:T.R,y:T.U,r:24},
    {x:T.L,y:T.D,r:24}, {x:500,y:T.D,r:23}, {x:T.R,y:T.D,r:24}
  ];
  const pocketNames = ['فوك يسار','فوك وسط','فوك يمين','جوه يسار','جوه وسط','جوه يمين'];
  const ballColors = ['#f7f7f7','#e7ba2d','#287aca','#c34c56','#663aa9','#e98d25','#2c9855','#7b3d31','#141619','#e7ba2d','#287aca','#c34c56','#663aa9','#e98d25','#2c9855','#7b3d31'];
  const ballOrder = [1,9,2,10,8,3,11,4,12,5,13,6,14,7,15];
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const distance = (a, b) => Math.hypot(a.x-b.x, a.y-b.y);
  const other = owner => owner === 'human' ? 'ai' : 'human';
  const isSpecial = id => id === 1 || id === 15;
  const ballGroup = id => id >= 1 && id <= 7 ? 'solid' : id >= 9 && id <= 15 ? 'stripe' : null;
  const groupLabel = g => g === 'solid' ? 'الكرات 1–7' : g === 'stripe' ? 'الكرات 9–15' : 'المجموعة غير محددة';
  let audioCtx = null, muted = false, frameTime = 0, accumulator = 0;
  let pendingAI = null, generation = 0, lastAIHeartbeat = 0;
  const state = {
    screen:'menu', difficulty:'medium', phase:'idle', turn:'human', group:null,
    balls:[], aim:{x:650,y:270}, power:58, called:null,
    special:{1:null,15:null}, shot:null, dragging:false, message:'', finished:false,shots:{human:0,ai:0}
  };
  const alive = id => state.balls.find(b => b.id === id && !b.out);
  const team = player => !state.group ? null : player === 'human' ? state.group : (state.group === 'solid' ? 'stripe' : 'solid');
  const ownedRemaining = player => state.balls.filter(b => !b.out && b.id !== 0 && ballGroup(b.id) === team(player)).length;
  const updateMessage = (message, icon='🎯') => { state.message=message; $('statusText').textContent=message; $('statusIcon').textContent=icon; };
  const clearComputer = () => { if (pendingAI) clearTimeout(pendingAI); pendingAI=null; generation++; };

  function sound(name) {
    if (muted) return;
    try {
      const Audio = window.AudioContext || window.webkitAudioContext;
      if (!Audio) return;
      audioCtx ??= new Audio();
      if (audioCtx.state === 'suspended') audioCtx.resume();
      const osc = audioCtx.createOscillator(), gain = audioCtx.createGain();
      const t=audioCtx.currentTime, tune={hit:[310,.037,.042],pocket:[145,.10,.065],cue:[160,.055,.09],win:[580,.24,.045]}[name]||[220,.03,.025];
      osc.type=name==='pocket'?'sine':'triangle';osc.frequency.setValueAtTime(tune[0],t);
      osc.frequency.exponentialRampToValueAtTime(tune[0]*.48,t+tune[1]);
      gain.gain.setValueAtTime(tune[2],t);gain.gain.exponentialRampToValueAtTime(.0001,t+tune[1]);
      osc.connect(gain).connect(audioCtx.destination);osc.start(t);osc.stop(t+tune[1]+.004);
    } catch (_) { /* audio is optional */ }
  }
  function validSpot(x,y,ignoreId) {
    if (x < T.L+T.r+4 || x > T.R-T.r-4 || y < T.U+T.r+4 || y > T.D-T.r-4) return false;
    return state.balls.every(b => b.out || b.id === ignoreId || Math.hypot(x-b.x,y-b.y) >= T.r*2+1.4);
  }
  function findOpenSpot(behind=true,ignoreId=0) {
    const start = behind ? 204 : 530;
    for (let k=0;k<35;k++) for (let j=0;j<11;j++) {
      const y=280+(k%2?1:-1)*Math.floor((k+1)/2)*22;
      const x=start+(j%2?1:-1)*Math.ceil(j/2)*24;
      if ((!behind || x <= T.head-T.r-5) && validSpot(x,y,ignoreId)) return {x,y};
    }
    return {x:behind?175:500,y:280};
  }
  function createRack() {
    state.balls = [{id:0,x:200,y:280,vx:0,vy:0,out:false}];
    let idx=0;
    for (let row=0;row<5;row++) for (let j=0;j<=row;j++) {
      const id=ballOrder[idx++];
      state.balls.push({id,x:694+row*20.5,y:280+(j-row/2)*23.0,vx:0,vy:0,out:false});
    }
  }
  function resetGame() {
    clearComputer();
    state.screen='game';state.phase='idle';state.turn='human';state.group=null;state.called=null;
    state.special={1:null,15:null};state.shot=null;state.aim={x:685,y:280};state.finished=false;
    state.power=58;state.dragging=false;state.shots={human:0,ai:0};frameTime=0;accumulator=0;
    $('power').value='58';$('powerText').textContent='58%';
    createRack();$('menuScreen').hidden=true;$('gameScreen').hidden=false;$('resultModal').hidden=true;document.body.classList.add('playing-mode');$('rotateOverlay').hidden=false;
    updateMessage('دورك! المس الطاولة لتحديد اتجاه الضربة، ثم اضغط «اضرب الكرة».');
    updateUI();resizeCanvas();requestAnimationFrame(resizeCanvas);draw();
    window.scrollTo({top:0,behavior:'instant'});
  }
  function toMenu() {
    clearComputer();state.screen='menu';state.phase='idle';state.finished=false;
    $('menuScreen').hidden=false;$('gameScreen').hidden=true;$('resultModal').hidden=true;document.body.classList.remove('playing-mode');$('rotateOverlay').hidden=true;
    if(document.fullscreenElement){document.exitFullscreen().catch(()=>{});}if(screen.orientation?.unlock){try{screen.orientation.unlock()}catch(_){}}
    window.scrollTo({top:0,behavior:'instant'});
  }
  function updateUI() {
    const human=state.turn==='human';
    $('humanPanel').classList.toggle('current',human && !state.finished);
    $('botPanel').classList.toggle('current',!human && !state.finished);
    $('turnText').textContent=state.finished?'انتهت المباراة':state.phase==='moving'?'الكرات تتحرك':human?'دورك':'دور الكمبيوتر';
    $('humanGroup').textContent=groupLabel(team('human'));
    $('botGroup').textContent=groupLabel(team('ai'));
    $('matchState').innerHTML=state.finished?'انتهت المباراة':'<i></i> المباراة جارية';
    // Numbered mini balls stay in 1–7 / 9–15 order and show pocketed progress.
    for (const [player,id] of [['human','humanBalls'],['ai','botBalls']]) {
      const g=team(player) || (player==='human'?'solid':'stripe');
      const el=$(id);el.replaceChildren();
      for(let n=1;n<=15;n++){
        if(ballGroup(n)!==g)continue;
        const s=document.createElement('span');
        s.className='rack-mini'+(!alive(n)?' potted':'')+(n>8?' striped':'');
        s.style.setProperty('--ball-color',ballColors[n]);
        s.textContent=String(n);
        s.setAttribute('aria-label','كرة '+n+(!alive(n)?' مدخلة':''));
        s.title='كرة '+n+(!alive(n)?' — دخلت':'');
        el.appendChild(s);
      }
    }
    const canShoot=state.screen==='game'&&state.turn==='human'&&state.phase==='idle'&&!state.finished;
    $('shootBtn').disabled=!canShoot;
    $('power').disabled=!canShoot;
    const calling=canShoot && legalTargets('human').some(b=>b.id===8);
    $('callArea').hidden=!calling;
    if (calling) updateCallButtons();
  }
  function updateCallButtons() {
    const root=$('pocketButtons');root.replaceChildren();
    for(let i=0;i<pockets.length;i++) {
      const b=document.createElement('button');b.type='button';b.className='pocket-button'+(state.called===i?' selected':'');b.textContent=pocketNames[i];
      b.addEventListener('click',()=>{state.called=i;updateMessage('تم تحديد التوب: '+pocketNames[i]+'. هسه صوب واضرب.','🎱');updateUI();draw();});
      root.appendChild(b);
    }
  }
  function legalTargets(player) {
    const g=team(player);
    const all=state.balls.filter(b=>!b.out&&b.id!==0&&b.id!==8);
    if (!g) return all;
    const remaining=all.filter(b=>ballGroup(b.id)===g);
    return remaining.length?remaining:(alive(8)?[alive(8)]:[]);
  }
  function beginShot(dx,dy,power) {
    if (state.screen!=='game'||state.phase!=='idle'||state.finished) return false;
    const cue=alive(0);if(!cue) return false;
    const len=Math.hypot(dx,dy);if(len<.0001)return false;
    state.shot={player:state.turn,first:null,potted:[],elapsed:0,contacted:false,called:state.called};
    state.shots[state.turn]++;
    const velocity=(clamp(power,12,100)/100)*14.6+2;
    cue.vx=dx/len*velocity;cue.vy=dy/len*velocity;
    state.phase='moving';state.called=state.called ?? null;
    updateMessage(state.turn==='human'?'الكرات تتحرك...':'الكمبيوتر يسدد...','🎱');sound('cue');updateUI();return true;
  }
  function shootHuman() {
    if(state.turn!=='human'||state.phase!=='idle')return;
    if(legalTargets('human').some(b=>b.id===8)&&state.called===null){updateMessage('اختار جيب التوب أولاً قبل ضرب السوداء.','⚠️');return;}
    const cue=alive(0);if(!cue)return;
    if(!beginShot(state.aim.x-cue.x,state.aim.y-cue.y,state.power))updateMessage('اختار اتجاه الضربة على الطاولة.','⚠️');
  }
  function pocketIndexFor(b) {
    for(let i=0;i<pockets.length;i++)if(distance(b,pockets[i])<pockets[i].r+3.5)return i;
    return -1;
  }
  function physicsStep() {
    const shot=state.shot;if(!shot)return;
    shot.elapsed+=1/60;
    const living=state.balls.filter(b=>!b.out);
    // Small physics increments prevent balls from passing through each other at higher power.
    for(let sub=0;sub<2;sub++) {
      for(const b of living) {if(b.out)continue;b.x+=b.vx*.5;b.y+=b.vy*.5;
        const idx=pocketIndexFor(b);
        if(idx>=0) { b.out=true;b.vx=0;b.vy=0;shot.potted.push({id:b.id,pocket:idx});sound('pocket');continue; }
        const vWall=.78;
        if(b.x<T.L+T.r){b.x=T.L+T.r;b.vx=Math.abs(b.vx)*vWall;}
        else if(b.x>T.R-T.r){b.x=T.R-T.r;b.vx=-Math.abs(b.vx)*vWall;}
        if(b.y<T.U+T.r){b.y=T.U+T.r;b.vy=Math.abs(b.vy)*vWall;}
        else if(b.y>T.D-T.r){b.y=T.D-T.r;b.vy=-Math.abs(b.vy)*vWall;}
      }
      for(let i=0;i<living.length;i++)for(let j=i+1;j<living.length;j++) {
        const a=living[i],b=living[j];if(a.out||b.out)continue;
        let dx=b.x-a.x,dy=b.y-a.y,d2=dx*dx+dy*dy,min=T.r*2;
        if(d2>min*min)continue;
        if(d2<.001){dx=.01;dy=.01;d2=.0002;}
        const d=Math.sqrt(d2),nx=dx/d,ny=dy/d,overlap=(min-d)/2;
        a.x-=nx*overlap;a.y-=ny*overlap;b.x+=nx*overlap;b.y+=ny*overlap;
        const vr=(a.vx-b.vx)*nx+(a.vy-b.vy)*ny;
        if(vr>0){const impulse=vr*.973;a.vx-=impulse*nx;a.vy-=impulse*ny;b.vx+=impulse*nx;b.vy+=impulse*ny;
          if(shot.first===null&&(a.id===0||b.id===0))shot.first=a.id===0?b.id:a.id;
          if(vr>.7)sound('hit');
        }
      }
    }
    let moving=false;
    for(const b of living){if(b.out)continue;const speed=Math.hypot(b.vx,b.vy);
      if(speed<.053){b.vx=0;b.vy=0;continue;}
      // rolling friction is stronger at low velocity, so the cue eventually stops.
      const friction=speed>2.8?.982:.969;
      b.vx*=friction;b.vy*=friction;moving=true;
    }
    if(!moving || shot.elapsed>12){
      for(const b of living){b.vx=0;b.vy=0;}
      state.phase='resolving';resolveShot();
    }
  }
  function respot(id) {
    const ball=state.balls.find(b=>b.id===id);
    if(!ball)return;
    const pos=findOpenSpot(true,id);ball.out=false;ball.x=pos.x;ball.y=pos.y;ball.vx=0;ball.vy=0;
  }
  function placeWhite(forPlayer) {
    let cue=state.balls.find(b=>b.id===0);
    const pos=findOpenSpot(true,0);
    cue.out=false;cue.vx=0;cue.vy=0;cue.x=pos.x;cue.y=pos.y;
    if(forPlayer==='human'){
      state.phase='placing';updateMessage('فاول: ضع الكرة البيضاء بإصبعك داخل المنطقة وراء الخط فقط.','⚪');
    } else {
      state.phase='idle';
      const target=legalTargets('ai')[0];
      if(target){const x=clamp(target.x-180,T.L+T.r+4,T.head-T.r-5);
        if(validSpot(x,clamp(target.y,T.U+T.r+5,T.D-T.r-5),0)){cue.x=x;cue.y=clamp(target.y,T.U+T.r+5,T.D-T.r-5);}
      }
    }
  }
  function resolveShot() {
    const shot=state.shot;if(!shot)return;
    state.shot=null;
    if(state.finished||state.screen!=='game')return;
    const player=shot.player,next=other(player),beforeGroup=state.group;
    const pocketed=shot.potted;
    const scratch=pocketed.some(p=>p.id===0);
    const fouls=[], legal=[];
    const owned=team(player);
    if(scratch)fouls.push('دخلت البيضاء بالجيب');
    if(shot.first!==null && (shot.first===8&&legalTargets(player).some(b=>b.id!==8) || owned && shot.first!==8&&ballGroup(shot.first)!==owned)) fouls.push('لمست كرة الخصم أولاً');
    if(!owned && shot.first===8)fouls.push('لمست السوداء قبل أوانها');
    // Only legal center pockets count for 1 and 15. The matching ball must go in the opposite center pocket.
    for(const p of pocketed){
      if(p.id===0||p.id===8)continue;
      let invalidSpecial=false;
      if(isSpecial(p.id)){
        const partner=p.id===1?15:1;
        if(![1,4].includes(p.pocket) || (state.special[partner]!==null&&state.special[partner]===p.pocket))invalidSpecial=true;
      }
      if(invalidSpecial){fouls.push('الكرة '+p.id+' دخلت بجيب مخالف');respot(p.id);continue;}
      if(owned && ballGroup(p.id)!==owned)fouls.push('دخلت كرة الخصم');
      legal.push(p.id);
      if(isSpecial(p.id))state.special[p.id]=p.pocket;
    }
    // Two specials in the same center during one shot are not a legal pair.
    if(state.special[1]!==null && state.special[1]===state.special[15]){
      const last=pocketed.slice().reverse().find(p=>isSpecial(p.id));
      if(last){state.special[last.id]=null;respot(last.id);const idx=legal.indexOf(last.id);if(idx>=0)legal.splice(idx,1);fouls.push('الكرة الثانية لازم بالجيب الوسطي المقابل');}
    }
    if(!beforeGroup && !fouls.length){const first=legal.find(id=>ballGroup(id));if(first)state.group=player==='human'?ballGroup(first):(ballGroup(first)==='solid'?'stripe':'solid');}
    const black=pocketed.find(p=>p.id===8);
    if(black){
      if(!team(player)||ownedRemaining(player)>0 ||fouls.length){finishGame(next,'دخلت السوداء قبل إكمال مجموعتك أو بضربة فاول.');return;}
      if(shot.called===null||black.pocket!==shot.called){finishGame(next,'دخلت السوداء بجيب غير المحدد بالتوب.');return;}
      finishGame(player,'دخلت السوداء بالجيب المحدد بالتوب!');return;
    }
    state.called=null;
    const wasOwn=team(player);
    const ownPotted=legal.some(id=>ballGroup(id)===wasOwn);
    const keepsTurn=!fouls.length && ownPotted;
    state.turn=keepsTurn?player:next;
    state.phase='idle';
    if(scratch)placeWhite(state.turn);
    if(scratch){ /* Scratch's behind-line placement takes precedence. */ }
    else if(fouls.length)updateMessage('فاول: '+[...new Set(fouls)].join('، ')+'. البيضاء تبقى بمكانها.','⚠️');
    else if(!beforeGroup&&state.group)updateMessage('تحددت المجموعات! '+groupLabel(team('human'))+' إلك.','🎱');
    else if(keepsTurn)updateMessage('دخلت كرة من مجموعتك، يستمر دورك.','✅');
    else updateMessage('انتهت الضربة، الدور انتقل للخصم.','🎯');
    updateUI();
    if(state.turn==='ai')queueAI();
    else if(state.phase==='idle'&&legalTargets('human').some(b=>b.id===8))updateMessage('وصلت للسوداء! اختار جيب التوب وبعدين صوب.','🎱');
  }
  function finishGame(winner,reason) {
    clearComputer();state.finished=true;state.phase='ended';state.called=null;
    $('resultEmoji').textContent=winner==='human'?'🏆':'🎱';
    $('resultTitle').textContent=winner==='human'?'فزت بالمباراة!':'الكمبيوتر فاز';
    $('resultBody').textContent=reason;
    $('resultModal').hidden=false;updateMessage(reason,winner==='human'?'🏆':'🎱');
    sound('win');updateUI();
  }
  function pathClear(ax,ay,bx,by,ignore) {
    const dx=bx-ax,dy=by-ay,d2=dx*dx+dy*dy;
    if(d2<1)return false;
    for(const b of state.balls){if(b.out||ignore.includes(b.id))continue;
      const t=clamp(((b.x-ax)*dx+(b.y-ay)*dy)/d2,0,1);
      if(Math.hypot(b.x-ax-t*dx,b.y-ay-t*dy)<T.r*2+.9)return false;
    }
    return true;
  }
  function chooseAIShot() {
    const cue=alive(0),targets=legalTargets('ai');if(!cue||!targets.length)return null;
    const options=[];
    for(const b of targets)for(let i=0;i<pockets.length;i++) {
      const p=pockets[i];
      if(isSpecial(b.id)&& (![1,4].includes(i)||(state.special[b.id===1?15:1]===i)))continue;
      let vx=p.x-b.x,vy=p.y-b.y,len=Math.hypot(vx,vy);if(len<2)continue;
      const ghost={x:b.x-vx/len*T.r*2.03,y:b.y-vy/len*T.r*2.03};
      if(ghost.x<T.L+T.r+1||ghost.x>T.R-T.r-1||ghost.y<T.U+T.r+1||ghost.y>T.D-T.r-1)continue;
      const a=pathClear(cue.x,cue.y,ghost.x,ghost.y,[0,b.id]),c=pathClear(b.x,b.y,p.x,p.y,[b.id]);
      const dist=distance(cue,ghost),cut=Math.abs((ghost.x-cue.x)*vy-(ghost.y-cue.y)*vx)/(dist*len+.01);
      const score=(a?0:3500)+(c?0:2100)+dist*.7+len*.5+cut*340+(b.id===8?90:0);
      options.push({b,pocket:i,ghost,score,dist,len});
    }
    options.sort((a,b)=>a.score-b.score);
    if(options.length)return options[0];
    // A fallback always fires at a legal target, even when the table is blocked.
    const target=targets.reduce((a,b)=>distance(cue,a)<distance(cue,b)?a:b);
    return {b:target,pocket:1,ghost:{x:target.x,y:target.y},dist:distance(cue,target),len:0,score:1e5};
  }
  function queueAI() {
    if(state.turn!=='ai'||state.screen!=='game'||state.finished)return;
    if(pendingAI)clearTimeout(pendingAI);
    const token=++generation;
    updateMessage('الكمبيوتر يفكّر بالضربة...','🤖');
    pendingAI=setTimeout(()=>{
      pendingAI=null;
      if(token!==generation||state.turn!=='ai'||state.finished||state.screen!=='game')return;
      if(state.phase==='placing'){placeWhite('ai');}
      if(state.phase!=='idle')return;
      try {
        const cue=alive(0),plan=chooseAIShot();
        if(!cue||!plan){ // Always hand control back on an unexpected table state.
          state.turn='human';state.phase='idle';updateMessage('الكمبيوتر مرر الدور.','🎯');updateUI();return;
        }
        const diff=state.difficulty;
        const error=diff==='easy'?.095:diff==='medium'?.033:.009;
        const dx=plan.ghost.x-cue.x,dy=plan.ghost.y-cue.y;
        const angle=Math.atan2(dy,dx)+(Math.random()*2-1)*error;
        const power=clamp(43+(plan.dist+plan.len)*.055+(diff==='easy'?Math.random()*12:4),37,96);
        state.called=plan.b.id===8?plan.pocket:null;
        if(!beginShot(Math.cos(angle),Math.sin(angle),power)){
          state.turn='human';state.phase='idle';updateUI();
        }
      }catch(err){console.error('AI recovered:',err);state.turn='human';state.phase='idle';state.shot=null;updateMessage('صار خلل بسيط بضربة الكمبيوتر؛ الدور إلك.','⚠️');updateUI();}
    }, 690);
  }
  function inputPosition(e) {
    const rect=canvas.getBoundingClientRect();return {x:(e.clientX-rect.left)*LOGICAL_WIDTH/rect.width,y:(e.clientY-rect.top)*LOGICAL_HEIGHT/rect.height};
  }
  function moveCueTo(pointer) {
    const c=alive(0);if(!c)return;
    const x=clamp(pointer.x,T.L+T.r+4,T.head-T.r-5),y=clamp(pointer.y,T.U+T.r+4,T.D-T.r-4);
    if(validSpot(x,y,0)){c.x=x;c.y=y;}
  }
  function handlePointer(e) {
    if(state.screen!=='game'||state.turn!=='human'||state.finished)return;
    if(state.phase!=='idle'&&state.phase!=='placing')return;
    const p=inputPosition(e);
    if(state.phase==='placing'){moveCueTo(p);draw();return;}
    if(legalTargets('human').some(b=>b.id===8)) {
      const index=pockets.findIndex(pock=>distance(p,pock)<37);
      if(index>=0){state.called=index;updateUI();updateMessage('توب السوداء: '+pocketNames[index]+'.','🎱');draw();return;}
    }
    state.aim=p;draw();
  }
  canvas.addEventListener('pointerdown',e=>{
    if(state.turn!=='human'||!['idle','placing'].includes(state.phase)||state.finished)return;
    state.dragging=true;try{canvas.setPointerCapture(e.pointerId);}catch(_){}
    handlePointer(e);
  });
  canvas.addEventListener('pointermove',e=>{if(state.dragging)handlePointer(e);});
  canvas.addEventListener('pointerup',()=>{
    if(state.dragging&&state.phase==='placing'){
      state.phase='idle';const c=alive(0);state.aim={x:c.x+200,y:c.y};
      updateMessage('تم وضع البيضاء خلف الخط. صوب واضرب.','🎯');updateUI();
    }
    state.dragging=false;
  });
  canvas.addEventListener('pointercancel',()=>{state.dragging=false;});

  function rounded(x,y,w,h,r=12) {ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
  function drawTable(){
    // All graphics are native canvas shapes; they remain crisp at high DPI.
    ctx.clearRect(0,0,LOGICAL_WIDTH,LOGICAL_HEIGHT);
    ctx.save();
    const bg=ctx.createLinearGradient(0,0,0,560);
    bg.addColorStop(0,'#121b32');bg.addColorStop(.5,'#263958');bg.addColorStop(1,'#0c1529');
    ctx.fillStyle=bg;ctx.fillRect(0,0,1000,560);
    // soft drop shadow / forged outer frame
    ctx.shadowColor='#03050b';ctx.shadowBlur=22;ctx.shadowOffsetY=11;
    rounded(6,6,988,548,36);ctx.fillStyle='#070b12';ctx.fill();
    ctx.shadowBlur=0;ctx.shadowOffsetY=0;
    const wood=ctx.createLinearGradient(0,0,980,540);
    wood.addColorStop(0,'#63351b');wood.addColorStop(.23,'#b8834c');wood.addColorStop(.5,'#65391f');wood.addColorStop(.78,'#bd8953');wood.addColorStop(1,'#4d2b1b');
    rounded(11,11,978,538,31);ctx.fillStyle=wood;ctx.fill();
    ctx.lineWidth=4;ctx.strokeStyle='#f5dbc0';ctx.stroke();
    rounded(26,25,948,510,26);ctx.fillStyle='#251a1a';ctx.fill();
    ctx.lineWidth=3;ctx.strokeStyle='#e6ae6e';ctx.stroke();
    const metal=ctx.createLinearGradient(0,29,0,532);
    metal.addColorStop(0,'#d0d4d3');metal.addColorStop(.1,'#fff1df');metal.addColorStop(.5,'#6e777b');metal.addColorStop(.9,'#f6ecdf');metal.addColorStop(1,'#c4c6c8');
    rounded(36,35,928,490,24);ctx.fillStyle=metal;ctx.fill();
    rounded(43,42,914,476,19);ctx.fillStyle='#40221b';ctx.fill();
    rounded(51,50,898,460,14);ctx.fillStyle='#082d75';ctx.fill();
    ctx.strokeStyle='#173d8b';ctx.lineWidth=10;ctx.stroke();
    const felt=ctx.createRadialGradient(500,255,10,500,280,510);
    felt.addColorStop(0,'#2c8ff4');felt.addColorStop(.48,'#1454cc');felt.addColorStop(.85,'#0d3194');felt.addColorStop(1,'#072576');
    ctx.fillStyle=felt;ctx.fillRect(T.L,T.U,T.R-T.L,T.D-T.U);
    ctx.save();ctx.beginPath();ctx.rect(T.L,T.U,T.R-T.L,T.D-T.U);ctx.clip();
    // Directional fine-grain cloth: deterministic, without loading any textures.
    ctx.lineWidth=.6;ctx.strokeStyle='#ffffff08';
    for(let i=0;i<190;i++){
      const xx=T.L+((i*97)%843),yy=T.U+((i*67)%406);
      ctx.beginPath();ctx.moveTo(xx,yy);ctx.lineTo(xx+19,yy-2);ctx.stroke();
    }
    const edgeShade=ctx.createLinearGradient(T.L,0,T.R,0);
    edgeShade.addColorStop(0,'#00135442');edgeShade.addColorStop(.16,'#00000000');edgeShade.addColorStop(.84,'#00000000');edgeShade.addColorStop(1,'#00135442');
    ctx.fillStyle=edgeShade;ctx.fillRect(T.L,T.U,T.R-T.L,T.D-T.U);
    ctx.restore();
    // The head line is intentionally visible; ball-in-hand never crosses it.
    ctx.strokeStyle='#e6f7ff80';ctx.lineWidth=1.65;
    ctx.beginPath();ctx.moveTo(T.head,T.U+3);ctx.lineTo(T.head,T.D-3);ctx.stroke();
    ctx.beginPath();ctx.arc(T.head,280,3,0,TWO_PI);ctx.fillStyle='#e6f7ff7d';ctx.fill();
    if(state.phase==='placing'){
      ctx.fillStyle='#fbd57133';ctx.fillRect(T.L+1,T.U+1,T.head-T.L-2,T.D-T.U-2);
      ctx.strokeStyle='#fbd571bb';ctx.setLineDash([7,7]);ctx.lineWidth=3;
      ctx.beginPath();ctx.moveTo(T.head,T.U);ctx.lineTo(T.head,T.D);ctx.stroke();ctx.setLineDash([]);
      ctx.textAlign='center';ctx.font='bold 16px Tahoma';ctx.fillStyle='#fff2bc';
      ctx.fillText('منطقة الفاول',180,119);
    }
    // Cushion border and seven diamonds across rails.
    ctx.strokeStyle='#072268';ctx.lineWidth=11;
    ctx.beginPath();ctx.rect(T.L-3,T.U-3,T.R-T.L+6,T.D-T.U+6);ctx.stroke();
    for(let i=0;i<7;i++)for(const y of [51,507]){
      const x=125+i*125;
      ctx.save();ctx.translate(x,y);ctx.rotate(PI/4);ctx.fillStyle='#f7e8c5';ctx.fillRect(-3.5,-3.5,7,7);ctx.restore();
    }
    for(let i=0;i<3;i++)for(const x of [52,947]){
      const y=140+i*140;ctx.save();ctx.translate(x,y);ctx.rotate(PI/4);
      ctx.fillStyle='#f7e8c5';ctx.fillRect(-3.5,-3.5,7,7);ctx.restore();
    }
    // pocket mouths: dark, recessed rings with brushed metal protectors
    for(let i=0;i<pockets.length;i++){
      const po=pockets[i],rr=po.r+9;
      ctx.beginPath();ctx.arc(po.x,po.y,rr,0,TWO_PI);ctx.fillStyle='#40251b';ctx.fill();
      ctx.lineWidth=4;ctx.strokeStyle='#c9c9b9';ctx.stroke();
      ctx.beginPath();ctx.arc(po.x,po.y,po.r+2,0,TWO_PI);ctx.fillStyle='#030610';ctx.fill();
      const voidGrad=ctx.createRadialGradient(po.x-5,po.y-6,0,po.x,po.y,po.r+3);
      voidGrad.addColorStop(0,'#01030a');voidGrad.addColorStop(.7,'#050911');voidGrad.addColorStop(1,'#1b202b');
      ctx.beginPath();ctx.arc(po.x,po.y,po.r-2,0,TWO_PI);ctx.fillStyle=voidGrad;ctx.fill();
      if(state.turn==='human'&&state.phase==='idle'&&legalTargets('human').some(b=>b.id===8)){
        ctx.beginPath();ctx.arc(po.x,po.y,po.r+14,0,TWO_PI);
        ctx.strokeStyle=state.called===i?'#ffe49e':'#d9eafa99';ctx.lineWidth=state.called===i?5:2;ctx.stroke();
      }
    }
    ctx.restore();
  }
  function ballPaint(b){
    const {x,y,id}=b,r=T.r;
    ctx.save();
    ctx.beginPath();ctx.ellipse(x+1.5,y+4.8,r*1.14,r*.73,0,0,TWO_PI);
    ctx.fillStyle='#03102c9c';ctx.fill();
    const isStripe=id>=9;
    const body=ctx.createRadialGradient(x-4.4,y-5,1,x,y,r*1.05);
    if(id===0){
      body.addColorStop(0,'#ffffff');body.addColorStop(.5,'#fffef9');body.addColorStop(1,'#9daec3');
    }else if(isStripe){
      body.addColorStop(0,'#ffffff');body.addColorStop(.63,'#fcfdff');body.addColorStop(1,'#9fabbf');
    }else{
      body.addColorStop(0,'#f7f9ff');body.addColorStop(.18,ballColors[id]);
      body.addColorStop(.76,ballColors[id]);body.addColorStop(1,id===8?'#030408':'#262939');
    }
    ctx.beginPath();ctx.arc(x,y,r,0,TWO_PI);ctx.fillStyle=body;ctx.fill();
    if(isStripe){
      ctx.save();ctx.beginPath();ctx.arc(x,y,r,0,TWO_PI);ctx.clip();
      const stripeGrad=ctx.createLinearGradient(x,y-r,x,y+r);
      stripeGrad.addColorStop(0,ballColors[id]);stripeGrad.addColorStop(.55,ballColors[id]);stripeGrad.addColorStop(1,'#101d37');
      ctx.fillStyle=stripeGrad;ctx.fillRect(x-r,y-r*.54,r*2,r*1.08);ctx.restore();
    }
    if(id!==0){
      ctx.beginPath();ctx.arc(x,y,r*.52,0,TWO_PI);ctx.fillStyle='#f9fbfb';ctx.fill();
      ctx.strokeStyle='#ffffff99';ctx.lineWidth=.45;ctx.stroke();
      ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillStyle='#0a1017';
      ctx.font=(id>=10?'900 9px Arial':'900 10px Arial');ctx.fillText(String(id),x,y+.35);
    }
    // specular reflection and lower crescent outline
    ctx.beginPath();ctx.ellipse(x-r*.35,y-r*.44,r*.24,r*.12,-.4,0,TWO_PI);
    ctx.fillStyle='#ffffffa9';ctx.fill();
    ctx.beginPath();ctx.arc(x,y,r,0,TWO_PI);ctx.lineWidth=.8;ctx.strokeStyle='#050b1d75';ctx.stroke();
    ctx.restore();
  }
  function drawGuide() {
    if(state.screen!=='game'||state.turn!=='human'||state.phase!=='idle')return;
    const c=alive(0);if(!c)return;
    let dx=state.aim.x-c.x,dy=state.aim.y-c.y,len=Math.hypot(dx,dy);
    if(len<3){dx=1;dy=0;len=1;}dx/=len;dy/=len;
    let max=900,hit=null;
    for(const b of state.balls){if(b.out||b.id===0)continue;
      const vx=b.x-c.x,vy=b.y-c.y,along=vx*dx+vy*dy,side=Math.abs(vx*dy-vy*dx);
      if(along<=T.r||side>=T.r*2)continue;
      const intersection=along-Math.sqrt((T.r*2)**2-side*side);
      if(intersection>0&&intersection<max){max=intersection;hit=b;}
    }
    ctx.save();ctx.setLineDash([7,9]);ctx.strokeStyle='#f3efd0bd';ctx.lineWidth=2.4;ctx.beginPath();ctx.moveTo(c.x+dx*17,c.y+dy*17);ctx.lineTo(c.x+dx*max,c.y+dy*max);ctx.stroke();ctx.setLineDash([]);
    if(hit){ctx.beginPath();ctx.arc(c.x+dx*max,c.y+dy*max,T.r,0,TWO_PI);ctx.strokeStyle='#ffffff85';ctx.lineWidth=2;ctx.stroke();}
    ctx.lineCap='round';ctx.strokeStyle='#27170f';ctx.lineWidth=11;ctx.beginPath();ctx.moveTo(c.x-dx*26,c.y-dy*26);ctx.lineTo(c.x-dx*245,c.y-dy*245);ctx.stroke();
    const gr=ctx.createLinearGradient(c.x-dx*240,c.y-dy*240,c.x-dx*20,c.y-dy*20);gr.addColorStop(0,'#67412b');gr.addColorStop(.55,'#b7824b');gr.addColorStop(.85,'#e1c198');gr.addColorStop(1,'#d0d8d6');
    ctx.strokeStyle=gr;ctx.lineWidth=6;ctx.beginPath();ctx.moveTo(c.x-dx*28,c.y-dy*28);ctx.lineTo(c.x-dx*240,c.y-dy*240);ctx.stroke();
    ctx.strokeStyle='#bed3d3';ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(c.x-dx*28,c.y-dy*28);ctx.lineTo(c.x-dx*38,c.y-dy*38);ctx.stroke();
    ctx.restore();
  }
  function draw() {
    if(state.screen!=='game')return;
    drawTable();
    for(const b of state.balls)if(!b.out)ballPaint(b);
    drawGuide();
    if(state.phase==='placing'&&state.turn==='human'){
      const c=alive(0);if(c){ctx.beginPath();ctx.arc(c.x,c.y,T.r+9,0,TWO_PI);ctx.strokeStyle='#f2db91';ctx.lineWidth=2;ctx.setLineDash([5,5]);ctx.stroke();ctx.setLineDash([]);}
    }
  }
  function frame(t) {
    requestAnimationFrame(frame);
    if(state.screen!=='game')return;
    if(state.turn==='ai'&&state.phase==='idle'&&!state.finished&&!pendingAI && t-lastAIHeartbeat>1200){ lastAIHeartbeat=t;queueAI(); }
    const dt=Math.min(48,t-(frameTime||t));frameTime=t;
    if(state.phase==='moving'){
      accumulator+=dt;let n=0;
      while(accumulator>=1000/60 && n++<4 && state.phase==='moving'){
        accumulator-=1000/60;physicsStep();
      }
    }else accumulator=0;
    draw();
  }
  function resizeCanvas(){
    const wrap=canvas.parentElement;
    if(!wrap || !wrap.clientWidth || !wrap.clientHeight)return;
    const displayScale=Math.min((wrap.clientWidth-12)/LOGICAL_WIDTH,(wrap.clientHeight-12)/LOGICAL_HEIGHT);
    const pxScale=Math.max(.12,displayScale);
    canvas.style.width=Math.round(LOGICAL_WIDTH*pxScale)+'px';
    canvas.style.height=Math.round(LOGICAL_HEIGHT*pxScale)+'px';
    const dpi=Math.min(3,Math.max(1,window.devicePixelRatio||1));
    const newWidth=Math.round(LOGICAL_WIDTH*dpi),newHeight=Math.round(LOGICAL_HEIGHT*dpi);
    if(canvas.width!==newWidth||canvas.height!==newHeight){
      canvas.width=newWidth;canvas.height=newHeight;
      ctx.setTransform(dpi,0,0,dpi,0,0);
    }
    if(state.screen==='game')draw();
  }
  const canvasObserver=new ResizeObserver(()=>resizeCanvas());
  canvasObserver.observe(canvas.parentElement);
  window.addEventListener('resize',resizeCanvas);
  window.addEventListener('orientationchange',()=>setTimeout(resizeCanvas,200));
  resizeCanvas();
  requestAnimationFrame(frame);
  document.querySelectorAll('.difficulty').forEach(b=>b.addEventListener('click',()=>{
    state.difficulty=b.dataset.level;
    document.querySelectorAll('.difficulty').forEach(x=>x.classList.toggle('chosen',x===b));
  }));
  $('startBtn').addEventListener('click',async()=>{resetGame();try{if(window.innerWidth<980&&!document.fullscreenElement){await document.documentElement.requestFullscreen();if(screen.orientation?.lock){try{await screen.orientation.lock('landscape');}catch(_){}}}}catch(_){}});
  $('resetBtn').addEventListener('click',resetGame);
  $('againBtn').addEventListener('click',resetGame);
  $('menuBtn').addEventListener('click',toMenu);
  $('backBtn').addEventListener('click',toMenu);
  $('shootBtn').addEventListener('click',shootHuman);
  $('power').addEventListener('input',e=>{state.power=+e.target.value;$('powerText').textContent=state.power+'%';});
  $('soundBtn').addEventListener('click',()=>{muted=!muted;$('soundBtn').textContent=muted?'♪̸':'♫';$('soundBtn').setAttribute('aria-label',muted?'تشغيل الصوت':'كتم الصوت');});
  $('rotateBtn').addEventListener('click',async()=>{try{if(!document.fullscreenElement)await document.documentElement.requestFullscreen();if(screen.orientation?.lock)await screen.orientation.lock('landscape');}catch(_){updateMessage('دوّر الموبايل للعرض يدوياً إذا ما يدعم جهازك القفل التلقائي.','📱')}requestAnimationFrame(resizeCanvas)});
  $('fullscreenBtn').addEventListener('click',async()=>{
    try{if(!document.fullscreenElement)await document.documentElement.requestFullscreen();else await document.exitFullscreen();
      if(screen.orientation?.lock&&document.fullscreenElement){try{await screen.orientation.lock('landscape');}catch(_){}}
    }catch(_){updateMessage('المتصفح ما يدعم ملء الشاشة، لف الموبايل بالعرض.','📱');}
  });
  window.addEventListener('keydown',e=>{if(e.code==='Space'&&state.screen==='game'&&!e.repeat){e.preventDefault();shootHuman();}});
  // Read-only test snapshot and controlled test hooks to check the turn-machine in automated browser QA.
  window.__BRIYALDO_TEST__={snapshot:()=>({turn:state.turn,phase:state.phase,group:state.group,balls:state.balls.map(b=>({id:b.id,x:b.x,y:b.y,out:b.out})),shot:!!state.shot,finished:state.finished,shots:state.shots}),forceBotTurn:()=>{if(state.screen==='game'&&!state.finished){clearComputer();state.phase='idle';state.turn='ai';updateUI();queueAI();}}};
})();