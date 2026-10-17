# Audio Priority Bar verification map

| User path | Recipe | Observable result |
| --- | --- | --- |
| Reorder synthetic speakers | Default `make verify` | Speaker B moves above A in the panel |
| Mute and unmute output | `APB_VERIFY_RECIPE=hosted make verify` | Fake volume falls to zero, restores, and controls keep their frames |
| Controls/settings layout | Hosted | Both appearances fit a 480-point panel under 700 points tall |
| Singleton file lock | Hosted | Independent process is refused while held and succeeds after release |
| Physical routing and Bartender placement | Attended only | Unverified by these recipes |

[Panel controls](panel-controls.md) describes driving and limits.
