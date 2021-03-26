// AngelScript
// Update Fixes

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor("Sw1ft");
	g_Module.ScriptInfo.SetContactInfo("Sw1ft#0116");

	g_Hooks.RegisterHook(Hooks::Player::PlayerTakeDamage, OnPlayerTakeDamage);
	g_Hooks.RegisterHook(Hooks::Game::EntityCreated, OnEntityCreated);
}

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

HookReturnCode OnPlayerTakeDamage(DamageInfo@ pDamageInfo)
{
	string sClassname = pDamageInfo.pInflictor.GetClassname();
	bool bIsGrenade = (sClassname == "grenade");
	
	if (pDamageInfo.pVictim.GetClassname() == "player" && (bIsGrenade || sClassname == "bolt"))
	{
		CBasePlayer@ pPlayer = cast<CBasePlayer@>(pDamageInfo.pVictim);
		int8 nWaterLevel = pPlayer.pev.waterlevel;
		float flArmor = pPlayer.pev.armorvalue;

		if (!pPlayer.IsAlive() || nWaterLevel > (bIsGrenade ? WATERLEVEL_FEET : WATERLEVEL_WAIST))
		{
			return HOOK_CONTINUE;
		}
		
		// Algorithms and constants taken from Half-Life 1 SDK, see 'combat.cpp' >> 'RadiusDamage' and 'DamageForce'
		float flAdjustedDamage, flDamage, flRadius, falloff;

		if (bIsGrenade)
		{
			flDamage = 100.0f; // grenade damage
			flRadius = 250.0f; // damage radius, if 'flRadius == 0.0f' then 'flRadius = flDamage * 2.5f'
			falloff = 0.4f;
		}
		else
		{
			flDamage = 40.0f; // xbow's bolt damage
			flRadius = 128.0f; // original radius
			falloff = 0.3125f;
		}

		Vector vecSrc = pDamageInfo.pInflictor.pev.origin;
		vecSrc.z += 1.0f;
		
		Vector vecSpot = pPlayer.BodyTarget(vecSrc);
		// falloff = flDamage / flRadius;

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

			if (!bIsGrenade) // non-SDK
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

			if (flArmor > 0.0f) // non-SDK
			{
				vecForce = vecForce * (1.0f / flArmor);
			}

			pPlayer.pev.velocity = vecVelocity + vecForce;
		}
	}
	
	return HOOK_CONTINUE;
}