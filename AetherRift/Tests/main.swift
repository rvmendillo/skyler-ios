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
let soak=ArenaSimulation(hero:1,difficulty:.veteran);soak.autoplay=true
for _ in 0..<18000 {soak.step(0.05);if soak.winner != nil{break}}
check(soak.units.allSatisfy{$0.p.x.isFinite && $0.p.y.isFinite && $0.hp.isFinite},"long match remains finite")
check(soak.units.count<300,"minion population stays bounded")
check(soak.heroes.contains{$0.level>1},"bots earn XP in combat")
check(soak.heroes.reduce(0){$0+$1.kills}>0,"bots engage and kill")
print("PASS: \(count) checks; simulated \(Int(soak.time)) seconds; \(soak.units.count) units; kills \(soak.heroes.reduce(0){$0+$1.kills}); winner \(String(describing:soak.winner))")
