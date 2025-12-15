Controls a single TRV using a scheduler when enabled.
When disabled, manual changes via the TRV knob or climate entity
are respected and not overridden.
For multiple TRVs, make a group of climate entities and use that as the target climate entity. E.g.:
climate:
  - platform: climate_group
    name: Living Room
    entities:
      - climate.trv_window
      - climate.trv_door
      
Create one scheduler helper per room:
Action: climate.set_temperature
Target: same TRV
Expose output sensor (e.g.):
sensor.livingroom_scheduler_temperature

That sensor feeds the blueprint.


Create one scheduler helper per room:

Action: climate.set_temperature

Target: same TRV

Expose output sensor (e.g.):

```
sensor.livingroom_scheduler_temperature
```

That sensor feeds the blueprint.
