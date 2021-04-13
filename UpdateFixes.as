// AngelScript
// Update Fixes
// Modify it as you wish

array<bool> g_bWaterJumping(33, false); // MAXCLIENTS + 1
array<bool> g_bDeadState(33, false);

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor("Sw1ft");
	g_Module.ScriptInfo.SetContactInfo("N/A");

	g_Hooks.RegisterHook(Hooks::Game::EntityCreated, OnEntityCreated);
	g_Hooks.RegisterHook(Hooks::Player::PlayerPostThink, OnPlayerPostThink);
	g_Hooks.RegisterHook(Hooks::Player::PlayerTakeDamage, OnPlayerTakeDamage);
}

// Snark's Collision
void OnEntityCreated_Post(const int idx)
{
	CBaseEntity@ pEntity = g_EntityFuncs.Instance(idx);
	
	if (pEntity !is null && pEntity.GetClassname() == "monster_snark" && pEntity.pev.owner !is null)
		pEntity.pev.iuser2 = 0;
}

HookReturnCode OnEntityCreated(CBaseEntity@ pEntity)
{
	g_Scheduler.SetTimeout("OnEntityCreated_Post", 0.0f, pEntity.entindex());
	
	return HOOK_CONTINUE;
}

// Water Jump / Ladder Fly
HookReturnCode OnPlayerPostThink(CBasePlayer@ pPlayer)
{
	int idx = pPlayer.entindex();

	if (pPlayer.pev.flags & FL_WATERJUMP != 0)
	{
		if (!g_bWaterJumping[idx])
			pPlayer.pev.velocity.z += 8.0f; // #define WJ_HEIGHT 8, done incorrectly but it works

		g_bWaterJumping[idx] = true;
	}
	else
	{
		g_bWaterJumping[idx] = false;
	}

	if (!pPlayer.IsAlive())
	{
		if (pPlayer.pev.movetype == MOVETYPE_FLY && !g_bDeadState[idx])
			pPlayer.pev.velocity = Vector(0.0f, 0.0f, 0.0f);

		g_bDeadState[idx] = true;
	}
	else
	{
		g_bDeadState[idx] = false;
	}

	return HOOK_CONTINUE;
}

// Damage Boosting
HookReturnCode OnPlayerTakeDamage(DamageInfo@ pDamageInfo)
{
	if (pDamageInfo.bitsDamageType == DMG_BLAST || pDamageInfo.bitsDamageType == (DMG_BLAST | DMG_ALWAYSGIB))
	{
		CBasePlayer@ pPlayer = cast<CBasePlayer@>(pDamageInfo.pVictim);
		int8 nWaterLevel = pPlayer.pev.waterlevel;

		if (nWaterLevel > WATERLEVEL_WAIST)
			return HOOK_CONTINUE;

		// Algorithms and constants taken from Half-Life 1 SDK, see 'combat.cpp' >> 'RadiusDamage' and 'DamageForce'
		float flAdjustedDamage, falloff;
		float flArmor = pPlayer.pev.armorvalue;
		float flDamage = pDamageInfo.pInflictor.pev.dmg;

		if (flDamage > 0.0f)
		{
			bool bIsXBow = (pDamageInfo.pInflictor.GetClassname() == "bolt");

			falloff = flDamage / (bIsXBow ? 128.0f : flDamage * 2.5f); // falloff = flDamage / flRadius

			Vector vecSrc = pDamageInfo.pInflictor.pev.origin;
			vecSrc.z += 1.0f;

			Vector vecSpot = pPlayer.BodyTarget(vecSrc);

			flAdjustedDamage = (vecSrc - vecSpot).Length() * falloff;
			flAdjustedDamage = flDamage - flAdjustedDamage;

			if (flAdjustedDamage > 0.0f)
			{
				// force = dmg * ((32 * 32 * 72.0) / (pev.size.x * pev.size.y * pev.size.z)) * 5; >>> player's box size is 32, 32, 72
				// when a player is ducking force will be multiplied by 2, but seems in Sven it works differently, or I'm missing something?
				
				float flForce = flAdjustedDamage * 5.0f;
				float flHeightDifference = 36.0f / pPlayer.pev.size.z;
				
				flForce *= flHeightDifference; // non-SDK solution

				Vector vecForce;
				Vector vecVelocity = pPlayer.pev.velocity;

				if (bIsXBow) // non-SDK
				{
					vecForce = (vecSpot - vecSrc).Normalize() * flForce;
					
					if (nWaterLevel == WATERLEVEL_WAIST)
					{
						vecForce = vecForce * 0.25f;
					}
					
					if (pPlayer.pev.flags & FL_ONGROUND != 0)
					{
						vecForce.z = 0.0f;
					}
					else if (flHeightDifference == 1.0f)
					{
						vecForce = vecForce * 0.5f;
					}
				}
				else
				{
					vecForce = ((pPlayer.pev.flags & FL_ONGROUND != 0) ? vecVelocity.Normalize() : (vecSpot - vecSrc).Normalize()) * flForce;
				}

				if (flArmor > 0.0f)
				{
					vecForce = vecForce * (1.0f / flArmor);
				}

				pPlayer.pev.velocity = vecVelocity + vecForce;
			}
		}
	}
	
	return HOOK_CONTINUE;
}
