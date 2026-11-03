extends RefCounted

## 双重攻击是 count=2 的多重攻击，每击分别结算；不把伤害简单乘倍数。
static func count(stats: Dictionary) -> int:
	return maxi(1,int(stats.get("skills",{}).get("multi_attack",{}).get("count",1)))

## 横向扫射的相邻攻击从两端交替起始；正向直线攻击保持同方向。
static func side(strike: int) -> float:
	return 1.0 if strike % 2 == 0 else -1.0
