Animações novas, classe de arma nova - Greataxe (Machado Pesado)
decidi que não vai ser só light, med, heavy, vai ser isso também, mas deve ter as subclasses `Dagger, Fists, Rapiers, Sword, Spears, Clubs, TwinBlades, Greataxes, Greatswords, Greathammers, Shield` cada um com animações diferentes e futuramente armas com animações dedicadas `legendaries ou algo do tipo`

aqui a animação do GreatAxe base:

---
GreataxeTwoHandsA1 111269660748188
GreataxeTwoHandsA2 126576927120908
GreataxeTwoHandsA3 86876023680893
GreatAxeAerial 81794080454334
GreatAxeCrit 103950024178748
GreatAxeCrouchIdle 108592538476304
GreataxeBlock 83891377944727
GreataxeCrouchWalk 135450333455556
GreataxeParryStart 103985732950863
GreataxeTwoHandsIdle 77740771646689
GreataxeTwoHandsParryR 124034155026056
GreataxeTwoHandsWalk 79529144099802
HeavyUppercut 125721624070954
---

o nome ja diz, Greataxe é para greataxe Two hands e One hand, Heavy é para todos os Heavy weap, Greataxe two hands é só para two hands

Ele vai ter o swingspeed de 0.83x da espada que é 1x, acho bom sempre garantir que as animações terão esses swingspeeds, pois é dificil ficar calculando na animação, a maioria ja está certo, mas eu não conferi na Wiki do deepwoken para saber como eles calculam o swingspeed de cada arma/mecânica (tipo flourish / uppercut e critical).

Critical deve deixar o player parado mas pode girar o personagem com o wasd, quando der critical, deve ser highlighted de vermelho (só heavy weapons)

Estou pensando em fazer algo como um inverse kinematics para sempre manter as mãos na arma, pois não consigo garantir que não bugue, mas isso é para discutirmos depois.

Não esqueça de garantir que as UIs todas sejam enabled, deixei todas enabled = false no studio para ficar menos poluida, mas quando entro no jogo, elas continuam escondidas.

