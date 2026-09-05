import Foundation
var count=0
func check(_ value:@autoclosure()->Bool,_ message:String){count+=1;if !value(){fputs("FAIL: \(message)\n",stderr);exit(1)}}
let g=ArenaSimulation(hero:4)
check(g.heroes.count==10,"5v5 roster")
check(g.units.filter{$0.kind == .tower}.count==18,"three turrets per lane and team")
let p=g.player
check(!g.vulnerable(g.units.first{$0.kind == .core && $0.team==1}!),"Nexus is protected by lanes")
let enemyTowers=g.units.filter{$0.kind == .tower && $0.team==1 && $0.lane==0}
check(enemyTowers.filter{g.vulnerable($0)}.count==1,"only outer turret is exposed")
for t in enemyTowers{t.hp=0}
check(g.vulnerable(g.units.first{$0.kind == .core && $0.team==1}!),"clearing one lane exposes Nexus")
p.gold=3000;check(g.buy(0,for:p),"buy boots at level 1")
check(g.price(Armory.items[6],for:p)==450,"component cost credited")
check(g.buy(6,for:p) && p.items == [6],"upgrade replaces component")
check(!g.buy(7,for:p),"one pair of boots enforced")
g.gain(p,xp:100000,gold:30000);check(p.level==15,"level cap")
g.autoLearn(p);check(p.ranks==[6,6,3],"all 15 skill ranks available")
let victim=g.heroes.first{$0.team==1}!
victim.p=p.p+V2(2,0);victim.shield=1000;let before=victim.hp
g.damage(victim,amount:100,source:p,magic:false);check(victim.hp==before && victim.shield<1000,"shield absorbs damage")
p.recall=6;g.damage(p,amount:100,source:victim,magic:false);check(p.recall==0,"damage interrupts recall")
victim.p=V2(90,50);check(!g.visible(victim,to:0),"unseen enemy hidden")
victim.p=Battlefield.brush[0];p.p=victim.p+V2(4,0);victim.revealed=0;check(!g.visible(victim,to:0),"brush conceals enemy")
p.p=victim.p+V2(1,0);check(g.visible(victim,to:0),"nearby brush enemy revealed")
let low=ArenaSimulation(hero:3);low.cast(2,by:low.player);check(low.player.cooldowns[2]==0,"ultimate locked at level 1")
let summon=ArenaSimulation(hero:0);let boss=summon.units.first{$0.kind == .colossus}!;boss.hp=1;boss.respawn=0;summon.damage(boss,amount:200,source:summon.player,magic:false,trueDamage:true);check(summon.units.contains{$0.kind == .summoned && $0.team==0},"Colossus sends a siege monster")
for h in Roster.heroes{let match=ArenaSimulation(hero:h.id,practice:true);match.autoLearn(match.player);for i in 0...2{match.player.cooldowns[i]=0;match.cast(i,by:match.player,direction:V2(1,1))};for _ in 0..<40{match.step(0.05)};check(match.player.hp.isFinite,"\(h.name) abilities remain finite")}
let hookMatch=ArenaSimulation(hero:6)
let hookTarget=hookMatch.heroes.first{$0.team==1}!
hookMatch.player.p=V2(48,48);hookTarget.p=V2(48,56);hookTarget.stun=5
hookMatch.cast(0,by:hookMatch.player,direction:V2(0,1))
for _ in 0..<10 {hookMatch.updateMissiles(0.05)}
check(hookTarget.p.distance(hookMatch.player.p)<2.1,"hook pulls only after projectile contact")
let control=ArenaSimulation(hero:4)
let hero=control.player;hero.p=V2(50,50)
let start=hero.p;control.move(hero,direction:V2(1,0),dt:0.05);let full=hero.p.distance(start)
hero.p=start;control.move(hero,direction:V2(0.25,0),dt:0.05)
check(abs(hero.p.distance(start)-full*0.25)<0.00001,"joystick magnitude scales speed")
hero.p=start;control.move(hero,direction:V2(0.01,0),dt:0.05);check(hero.p==start,"joystick dead zone")
hero.recall=5;control.move(hero,direction:V2(1,0),dt:0.05);check(hero.recall==0,"movement cancels recall")
hero.p=start;hero.stun=1;control.move(hero,direction:V2(1,0),dt:0.05);check(hero.p==start,"stun blocks movement");hero.stun=0
let ally=control.heroes.first{$0.team==0 && $0.id != hero.id}!
let allyHP=ally.hp;control.damage(ally,amount:999,source:hero,magic:false,trueDamage:true);check(ally.hp==allyHP,"friendly damage rejected")
control.lockTarget(ally.id);check(control.selectedTarget==nil,"cannot lock an ally")
let opponents=control.heroes.filter{$0.team==1}
for opponent in opponents{opponent.p=V2(95,80)}
let first=opponents[0],second=opponents[1];first.p=start+V2(4,0);second.p=start+V2(7,0);first.hp=900;second.hp=800
control.targetPriority = .lowestHealth;check(control.attackTarget(for:hero,range:9)?.id==second.id,"lowest absolute health targeting")
control.targetPriority = .lowestPercent;check(control.attackTarget(for:hero,range:9)?.id==first.id,"lowest percent health targeting")
control.targetPriority = .closest;check(control.attackTarget(for:hero,range:9)?.id==first.id,"nearest targeting")
control.lockTarget(second.id);check(control.attackTarget(for:hero,range:9)?.id==second.id,"manual lock overrides automatic priority")
control.lockTarget(second.id);check(control.selectedTarget==nil,"second portrait tap clears lock")
control.lockTarget(first.id);control.attackMode=1
let minion=control.add(.melee,1,start+V2(2,0),400)
check(control.attackTarget(for:hero,range:9)?.id==minion.id,"minion mode ignores hero lock")
control.attackMode=2
let tower=control.units.first{$0.kind == .tower && $0.team==1 && $0.tier==1}!
tower.p=start+V2(3,0)
check(control.attackTarget(for:hero,range:9)?.id==tower.id,"turret mode ignores hero lock")
control.attackMode=0;control.selectedTarget=ally.id
check(control.attackTarget(for:hero,range:9)?.team==1,"stale allied target cannot cause friendly fire")
control.selectedTarget=nil;first.hp=0;second.p=start+V2(10,0);minion.hp=0;tower.hp=0;hero.p=start
control.movement = .zero;control.attackAssist=true;control.playerAttack(hero,dt:0.05)
check(hero.p.x>start.x,"holding attack approaches nearby target")
hero.p=start;control.movement=V2(-1,0);control.playerAttack(hero,dt:0.05)
check(hero.p==start,"manual joystick overrides attack approach")
control.movement = .zero;control.attackAssist=false;control.playerAttack(hero,dt:0.05)
check(hero.p==start,"attack approach can be disabled")
let paused=ArenaSimulation(hero:1);paused.paused=true;paused.step(0.05)
check(paused.time==0,"paused match does not advance")
let deadShop=ArenaSimulation(hero:1);deadShop.player.hp=0;deadShop.player.respawn=10;deadShop.player.gold=5000
_=deadShop.buy(3,for:deadShop.player);check(deadShop.player.hp==0 && !deadShop.player.alive,"buying health cannot revive a dead hero")
let execution=ArenaSimulation(hero:2,practice:true);execution.autoLearn(execution.player);execution.player.p=V2(40,50)
let far=execution.heroes.first{$0.team==1}!;far.p=V2(48,50)
execution.cast(2,by:execution.player);check(execution.player.cooldowns[2]==0,"out-of-range execution does not consume ultimate")
let spellTest=ArenaSimulation(hero:0,spell:.purify);spellTest.player.stun=3;spellTest.player.slow=2;spellTest.castSpell(spellTest.player)
check(spellTest.player.stun==0 && spellTest.player.slow==0 && spellTest.player.immunity>0,"Purify clears crowd control")
let soak=ArenaSimulation(hero:1,difficulty:.veteran);soak.autoplay=true
for _ in 0..<30000 {soak.step(0.05);if soak.winner != nil{break}}
check(soak.units.allSatisfy{$0.p.x.isFinite && $0.p.y.isFinite && $0.hp.isFinite},"long match remains finite")
check(soak.units.count<300,"minion population stays bounded")
check(soak.heroes.contains{$0.level>1},"bots earn XP in combat")
check(soak.heroes.reduce(0){$0+$1.kills}>0,"bots engage and kill")
check(soak.winner != nil,"full bot match reaches a victory")
print("PASS: \(count) checks; simulated \(Int(soak.time)) seconds; \(soak.units.count) units; kills \(soak.heroes.reduce(0){$0+$1.kills}); winner \(String(describing:soak.winner))")
