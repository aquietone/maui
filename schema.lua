local schema = {
    General={
        Properties={
            CampRadius={
                Type='NUMBER',
                Min=0
            },
            CampRadiusExceed={
                Type='NUMBER',
                Min=0
            },
            ReturnToCamp={
                Type='SWITCH'
            },
            ReturnToCampAccuracy={
                Type='NUMBER',
                Min=5
            },
            ChaseAssist={
                Type='SWITCH'
            },
            ChaseDistance={
                Type='NUMBER',
                Min=0
            },
            MedOn={
                Type='SWITCH'
            },
            MedStart={
                Type='NUMBER',
                Min=0,
                Max=100
            },
            SitToMed={
                Type='NUMBER',
                Min=0
            },
            LootOn={
                Type='SWITCH'
            },
            RezAcceptOn={--switch + extra option 0/1|96
                Type='MULTIPART',
                Parts={
                    [1]={
                        Name='On|Off',
                        Type='SWITCH'
                    },
                    [2]={
                        Name='Min. Pct',
                        Type='NUMBER',
                        Min=0,
                        Max=100
                    }
                }
            },
            AcceptInvitesOn={
                Type='SWITCH'
            },
            GroupWatchOn={--switch + extra options 0/1/2/3|MedAt%|Classes
                Type='STRING'
            },
            CastingInterruptOn={
                Type='SWITCH'
            },
            EQBCOn={--switch + extra option
                Type='STRING'
            },
            DanNetOn={--switch + extra option
                Type='STRING'
            },
            DanNetDelay={
                Type='NUMBER'
            },
            MiscGem={
                Type='NUMBER',
                Min=1,
                Max=13
            },
            MiscGemLW={
                Type='NUMBER',
                Min=1,
                Max=13
            },
            MiscGemRemem={
                Type='SWITCH'
            },
            TwistOn={
                Type='SWITCH'
            },
            TwistMed={
                Type='STRING'
            },
            TwistWhat={
                Type='STRING'
            },
            GroupEscapeOn={
                Type='SWITCH'
            },
            CampfireOn={
                Type='SWITCH'
            },
            DPSMeter={
                Type='SWITCH'
            },
            ScatterOn={
                Type='SWITCH'
            },
            CheerPeople={
                Type='SWITCH'
            },
            BeepOnNamed={
                Type='SWITCH'
            },
            BuffWhileChasing={
                Type='SWITCH'
            }
            --Role
            --GemStuckAbility
            --HoTTOn
            --MoveCloserIfNoLOS
            --IRCOn
            --CastRetries
            --SwitchWithMA
            --TravelOnHorse
        }
    },
    SpellSet={
        Properties={
            LoadSpellSet={
                Type='NUMBER',
                Min=0,
                Max=2
            },
            SpellSetName={
                Type='STRING'
            }
        }
    },
    Melee={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            AssistAt={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            FaceMobOn={
                Type='SWITCH'
            },
            MeleeDistance={
                Type='NUMBER',
                Min=0
            },
            StickHow={
                Type='STRING'
            },
            MeleeTwistOn={
                Type='SWITCH'
            },
            MeleeTwistWhat={
                Type='STRING'
            },
            AutoFireOn={
                Type='SWITCH'
            },
            UseMQ2Melee={
                Type='SWITCH'
            },
            Autohide={
                Type='SWITCH'
            },
            BeforeCombat={
                Type='SPELL'
            },
            TargetSwitchingOn={
                Type='SWITCH'
            },
            DismountDuringFights={
                Type='SWITCH'
            }
            --TankAllMobs
        }
    },
    DPS={
        Controls={
            On={
                Type='NUMBER',
                Min=0,
                Max=2
            },
            COn=true
        },
        Properties={
            DPS={
                Type='LIST',
                Max=40,
                Conditions=true
            },
            DPSSkip={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            DPSInterval={
                Type='NUMBER',
                Min=0
            },
            DebuffAllOn={
                Type='NUMBER',
                Min=0,
                Max=2
            }
        }
    },
    Buffs={
        Controls={
            On={
                Type='SWITCH'
            },
            COn=true
        },
        Properties={
            Buffs={
                Type='LIST',
                Max=20,
                Conditions=true
            },
            RebuffOn={
                Type='SWITCH'
            },
            CheckBuffsTimer={
                Type='NUMBER',
                Min=0
            },
            PowerSource={
                Type='STRING'
            },
            BegOn={
                Type='SWITCH'
            },
            BegPermissions={
                Type='STRING'
            },
            Beg={
                Type='LIST',
                Max=20,
                Conditions=false
            }
        }
    },
    Heals={
        Controls={
            On={
                Type='SWITCH'
            },
            COn=true
        },
        Properties={
            Heals={
                Type='LIST',
                Max=15,
                Conditions=true
            },
            XTarHeal={
                Type='STRING'
            },
            AutoRezOn={
                Type='SWITCH'
            },
            AutoRezWith={
                Type='SPELL'
            },
            HealGroupPetsOn={
                Type='SWITCH'
            },
            InterruptHeals={
                Type='NUMBER',
                Min=0
            }
        }
    },
    Cures={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            Cures={
                Type='LIST',
                Max=5,
                Conditions=true
            }
        }
    },
    Mez={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Classes={brd=1,enc=1},
        Properties={
            MezRadius={
                Type='NUMBER',
                Min=0
            },
            MezMinLevel={
                Type='NUMBER',
                Min=1
            },
            MezMaxLevel={
                Type='NUMBER',
                Min=1
            },
            MezStopHPs={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            MezSpell={
                Type='SPELL'
            },
            MezAESpell={
                Type='SPELL'
            }
        }
    },
    Pet={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            PetSpell={
                Type='SPELL'
            },
            PetFocus={
                Type='SPELL'
            },
            PetShrinkOn={
                Type='SWITCH'
            },
            PetShrinkSpell={
                Type='SPELL'
            },
            PetHoldOn={
                Type='SWITCH'
            },
            PetBuffsOn={
                Type='SWITCH'
            },
            PetBuffs={
                Type='LIST',
                Max=8,
                Conditions=false
            },
            PetCombatOn={
                Type='SWITCH'
            },
            PetAssistAt={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            PetBreakMezSpell={
                Type='SPELL'
            },
            PetRampPullWait={
                Type='SWITCH'
            },
            PetSuspend={
                Type='SWITCH'
            },
            MoveWhenHit={
                Type='SWITCH'
            }
            --PetToysSize
        }
    },
    Pull={
        Properties={
            PullWith={
                Type='STRING'
            },
            MaxRadius={
                Type='NUMBER',
                Min=1
            },
            MaxZRange={
                Type='NUMBER',
                Min=1
            },
            PullWait={
                Type='NUMBER',
                Min=0
            },
            PullRoleToggle={
                Type='SWITCH'
            },
            PullTwistOn={
                Type='SWITCH'
            },
            ChainPull={
                Type='SWITCH'
            },
            ChainPullHP={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            PullPause={
                Type='STRING'
            },
            PullLevel={
                Type='MULTIPART',
                Parts={
                    [1]={
                        Name='Min Level',
                        Type='NUMBER',
                        Min=1
                    },
                    [2]={
                        Name='Max Level',
                        Type='NUMBER',
                        Min=1
                    }
                }
            },
            PullMeleeStick={
                Type='SWITCH'
            },
            UseWayPointZ={
                Type='SWITCH'
            },
            PullArcWidth={
                Type='NUMBER',
                Min=0,
                Max=360
            }
        }
    },
    Merc={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            MercAssistAt={
                Type='NUMBER',
                Min=1,
                Max=100
            },
            AutoRevive={
                Type='SWITCH'
            }
        }
    },
    Burn={
        Controls={
            COn=true
        },
        Properties={
            Burn={
                Type='LIST',
                Max=15,
                Conditions=true
            },
            BurnAllNamed={
                Type='NUMBER',
                Min=0,
                Max=2
            },
            UseTribute={
                Type='SWITCH'
            },
            BurnText={
                Type='STRING'
            }
        }
    },
    AFKTools={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            AFKGMAction={
                Type='NUMBER',
                Min=0,
                Max=4
            },
            AFKPCRadius={
                Type='NUMBER',
                Min=0
            },
            CampOnDeath={
                Type='SWITCH'
            },
            ClickBackToCamp={
                Type='SWITCH'
            },
            BeepOnNamed={
                Type='SWITCH'
            }
        }
    },
    GoM={
        Controls={
            On={
                Type='SWITCH'
            },
            COn=true
        },
        Properties={
            GoM={
                Type='LIST',
                Max=5,
                Conditions=true
            }
        }
    },
    AE={
        Controls={
            On={
                Type='SWITCH'
            }
        },
        Properties={
            AERadius={
                Type='NUMBER',
                Min=0
            },
            AE={
                Type='LIST',
                Max=10,
                Conditions=false
            }
        }
    },
    Aggro={
        Controls={
            On={
                Type='SWITCH'
            },
            COn=true
        },
        Properties={
            Aggro={
                Type='LIST',
                Max=5,
                Conditions=true
            }
        }
    },
    OhShit={
        Controls={
            On={
                Type='SWITCH'
            },
            COn=true
        },
        Properties={
            OhShit={
                Type='LIST',
                Max=10,
                Conditions=true
            }
        }
    }
    -- Gmail
    -- Bandolier
}

return schema
