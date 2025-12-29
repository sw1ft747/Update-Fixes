// Sven Co-op Update Fixes
// Brings back to the game most of gameplay-critical and funny bugs that bozo devs fixed/broke, what a productive game development, yeah?
// The actual goal was to preserve all features and funny bugs of version 5.22, but does that matter now? The game is in a complete despair..

uint g_iVersion = 526;
array<bool> g_bWaterJumping( 33, false );
array<bool> g_bDeadState( 33, false );

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "Sw1ft / xWhitey" );
	g_Module.ScriptInfo.SetContactInfo( "https://discord.gg/j2ERvTT263" );

    g_iVersion = g_Game.GetGameVersion();
    
    if ( g_iVersion >= 526 )
    {
        g_Hooks.RegisterHook( Hooks::Monster::MonsterTakeDamage, OnMonsterTakeDamage );
        g_Hooks.RegisterHook( Hooks::Player::PlayerEnteredObserver, OnPlayerEnteredObserver );
    }

    if ( g_iVersion >= 524 )
	{
        g_Hooks.RegisterHook( Hooks::Game::EntityCreated, OnEntityCreated );
    }

    if ( g_iVersion >= 523 )
    {
        g_Hooks.RegisterHook( Hooks::Player::PlayerPostThink, OnPlayerPostThink );
        g_Hooks.RegisterHook( Hooks::Player::PlayerTakeDamage, OnPlayerTakeDamage );
    }
}

void MapInit()
{
	g_bDeadState = g_bWaterJumping = array<bool>( 33, false );
}

// Sinking (removed in 5.26 WTH)
HookReturnCode OnPlayerEnteredObserver( CBasePlayer@ pPlayer )
{
    Observer@ pObserver = pPlayer.GetObserver();
    if ( pObserver is null )
        return HOOK_CONTINUE;

    if ( pObserver.HasCorpse() )
    {
        CBaseEntity@ pCorpse = null;

        while ( ( @pCorpse = g_EntityFuncs.FindEntityByClassname( pCorpse, "deadplayer" ) ) !is null )
        {
            if ( pCorpse.pev.renderamt == pPlayer.entindex() )
            {
                pCorpse.pev.effects &= ~EF_NOINTERP;
                g_Scheduler.SetTimeout( "CorpseThink", 0.0f, EHandle( pCorpse ) );
                break;
            }
        }
    }

    return HOOK_CONTINUE;
}

// @xWhitey's fix, though I removed custom entity since it crashes the server sometimes
void CorpseThink( const EHandle hEntity )
{
    CBaseEntity@ pEntity = hEntity.GetEntity();
    if ( pEntity is null )
        return;

    TraceResult tr;
    g_Utility.TraceHull( pEntity.pev.origin, pEntity.pev.origin, ignore_monsters, human_hull, pEntity.edict(), tr );
    if ( tr.fInOpen == 1 )
    {
        g_Utility.TraceHull( pEntity.pev.origin, pEntity.pev.origin - Vector( 0, 0, 8192 ), ignore_monsters, human_hull, pEntity.edict(), tr );

        const float flDistance = pEntity.pev.origin.z - tr.vecEndPos.z;
        if ( flDistance >= 1.f )
        {
            g_EntityFuncs.SetOrigin( pEntity, pEntity.pev.origin - Vector( 0, 0, 1 ) );
            pEntity.pev.solid = SOLID_BBOX;
        }
        else
        {
            pEntity.pev.solid = SOLID_NOT;
        }
    }
    else
    {
        g_EntityFuncs.SetOrigin( pEntity, pEntity.pev.origin - Vector( 0, 0, 100.0 * g_Engine.frametime ) );
        pEntity.pev.solid = SOLID_BBOX;
    }

	g_Scheduler.SetTimeout( "CorpseThink", 0.1f, EHandle( pEntity ) );
}

// Fix of a 5.26 bug when really heavy monsters get easily boosted from explosions @xWhitey
HookReturnCode OnMonsterTakeDamage( DamageInfo@ pDamageInfo )
{
    CBaseEntity@ pVictim = pDamageInfo.pVictim;
    string szClassname = pVictim.GetClassname();
    if ( szClassname == "monster_bigmomma" || szClassname == "monster_gargantua" || szClassname == "monster_babygarg" )
    {
        pDamageInfo.bitsDamageType &= ~DMG_BLAST;
    }

    return HOOK_CONTINUE;
}

// Snark's Collision (disabled by default in 5.24)
void OnEntityCreated_Post( const EHandle hEntity )
{
	if ( !hEntity )
		return;

	CBaseEntity@ pEntity = hEntity.GetEntity();
	
	if ( pEntity.GetClassname() == "monster_snark" && pEntity.pev.owner !is null )
		pEntity.pev.iuser2 = 0;
}

HookReturnCode OnEntityCreated( CBaseEntity@ pEntity )
{
	g_Scheduler.SetTimeout( "OnEntityCreated_Post", 0.0f, EHandle( pEntity ) );
	
	return HOOK_CONTINUE;
}

// Water Jump (broken in 5.23)
HookReturnCode OnPlayerPostThink( CBasePlayer@ pPlayer )
{
	int ndx = pPlayer.entindex();

    // Water jump
	if ( pPlayer.pev.flags & FL_WATERJUMP != 0 )
	{
		if ( !g_bWaterJumping[ ndx ] )
			pPlayer.pev.velocity.z += 8.0f; // #define WJ_HEIGHT 8, done incorrectly but it works

		g_bWaterJumping[ ndx ] = true;
	}
	else
	{
		g_bWaterJumping[ ndx ] = false;
	}

    // Fixed flying corpses of players when they die on ladder (broken in 5.24 iirc)
    if ( g_iVersion == 524 )
    {
        if ( !pPlayer.IsAlive() )
        {
            if ( pPlayer.pev.movetype == MOVETYPE_FLY && !g_bDeadState[ ndx ] )
                pPlayer.pev.velocity = g_vecZero;

            g_bDeadState[ ndx ] = true;
        }
        else
        {
            g_bDeadState[ ndx ] = false;
        }
    }

	return HOOK_CONTINUE;
}

// Damage Boosting from explosions (broken in 5.23)
HookReturnCode OnPlayerTakeDamage( DamageInfo@ pDamageInfo )
{
	CBasePlayer@ pPlayer = cast<CBasePlayer@>( pDamageInfo.pVictim );

	if ( pDamageInfo.bitsDamageType == DMG_BLAST || pDamageInfo.bitsDamageType == ( DMG_BLAST | DMG_ALWAYSGIB ) )
	{
		const int8 nWaterLevel = pPlayer.pev.waterlevel;

		if ( nWaterLevel > WATERLEVEL_WAIST )
			return HOOK_CONTINUE;

		// Algorithms and constants taken from Half-Life 1 SDK, see 'combat.cpp' >> 'RadiusDamage' and 'DamageForce'
		float flAdjustedDamage, falloff;
		const float flArmor = pPlayer.pev.armorvalue;
		const float flDamage = pDamageInfo.pInflictor.pev.dmg;
		
		if ( flDamage > 0.0f )
		{
			const bool bIsXBow = ( pDamageInfo.pInflictor.GetClassname() == "bolt" );

			falloff = flDamage / ( bIsXBow ? 128.0f : flDamage * 2.5f ); // falloff = flDamage / flRadius

			Vector vecSrc = pDamageInfo.pInflictor.pev.origin;
			vecSrc.z += 1.0f;

			const Vector vecSpot = pPlayer.BodyTarget( vecSrc );

			flAdjustedDamage = ( vecSrc - vecSpot ).Length() * falloff;
			flAdjustedDamage = flDamage - flAdjustedDamage;

			if ( flAdjustedDamage > 0.0f )
			{
				// force = dmg * ( ( 32 * 32 * 72.0 ) / ( pev.size.x * pev.size.y * pev.size.z ) ) * 5; >>> player's box size is 32, 32, 72
				// when a player is ducking force will be multiplied by 2, but seems like in Sven it works differently, maybe I miss something?
				
				float flForce = flAdjustedDamage * 5.0f;
				float flHeightDifference = 36.0f / pPlayer.pev.size.z;
				
				flForce *= flHeightDifference; // non-SDK solution

				Vector vecForce;
				Vector vecVelocity = pPlayer.pev.velocity;

				if ( bIsXBow ) // non-SDK
				{
					vecForce = ( vecSpot - vecSrc ).Normalize() * flForce;
					
					if ( nWaterLevel == WATERLEVEL_WAIST )
					{
						vecForce = vecForce * 0.25f;
					}
					
					if ( pPlayer.pev.flags & FL_ONGROUND != 0 )
					{
						vecForce.z = 0.0f;
					}
					else if ( flHeightDifference == 1.0f )
					{
						vecForce = vecForce * 0.5f;
					}
				}
				else
				{
					vecForce = ( ( pPlayer.pev.flags & FL_ONGROUND != 0 ) ? vecVelocity.Normalize() : ( vecSpot - vecSrc ).Normalize() ) * flForce;
				}

				if ( flArmor > 0.0f )
				{
					vecForce = vecForce * ( 1.0f / flArmor );
				}

				pPlayer.pev.velocity = vecVelocity + vecForce;
			}
		}
	}

	return HOOK_CONTINUE;
}
