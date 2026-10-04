import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("kitchenin") {
            dimension = "flavor-type"
            applicationId = "com.kitchenin.app"
            resValue(type = "string", name = "app_name", value = "KitchenIn")
        }
    }

    buildFeatures.resValues = true
}