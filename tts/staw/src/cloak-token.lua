-- STA2E_CLOAK_ECHO_20261025: either face opens the shared Sensor Echo GUI.
function STA2E_DrawCloakEcho()
    self.clearButtons()
    for _,underside in ipairs({false,true}) do
        self.createButton({function_owner=self,click_function="STA2E_Echo",label="ECHO",
            position={0,underside and -0.34 or 0.34,0.72},rotation=underside and {0,0,180} or {0,0,0},
            width=720,height=400,font_size=150,color={0.08,0.18,0.28,0.94},font_color={1,1,1},
            tooltip="Sensor Echo: choose left/right, template and forward/lateral/back placement."})
    end
end
function onLoad() STA2E_DrawCloakEcho() end
function STA2E_Echo(_,color)
    Global.call("STA2E_CloakEcho",{color=color,source=self})
end
