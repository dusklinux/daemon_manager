// One privileged operation keeps service and feature controls serialized.
enum FeatureBatchControl {
    static let script = #"""
def apply_feature_batch(operations, live, air_drop_control, interface_control):
    code = (apply_live if live else apply)(operations)
    if code:
        return code
    if air_drop_control is not None:
        helper, enabled = air_drop_control
        code = air_drop(helper, "on" if enabled else "off")
        if code:
            return code
        print("[done] AirDrop policy", flush=True)
    if interface_control is not None:
        asset, disabled = interface_control
        ui_control(asset, "set", {"controlCenter": disabled, "appLibrary": disabled})
        print("[done] SpringBoard interfaces", flush=True)
    return 0
"""#
}
