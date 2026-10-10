"""Initial curves for Audacious's ten-band equalizer (31 Hz to 16 kHz)."""
BUILTINS = [
    {'id':'builtin:neutral','name':'Neutral','preamp':0.0,'bands':[0.0]*10,'user':False},
    {'id':'builtin:bass','name':'Bass','preamp':-5.0,'bands':[5,4,3,1,0,-1,-1,0,0,0],'user':False},
    {'id':'builtin:lounge','name':'Lounge','preamp':-2.0,'bands':[2,2,1,0,-1,-1,0,1,2,1],'user':False},
    {'id':'builtin:speech','name':'Speech','preamp':-3.0,'bands':[-4,-3,-2,0,2,3,3,2,0,-2],'user':False},
    {'id':'builtin:rock','name':'Rock','preamp':-3.0,'bands':[3,2,0,-1,-2,0,1,2,3,3],'user':False},
]

def matches(preset, preamp, bands):
    return len(bands) == 10 and abs(preset['preamp']-preamp) < .05 and all(abs(a-b)<.05 for a,b in zip(preset['bands'], bands))
