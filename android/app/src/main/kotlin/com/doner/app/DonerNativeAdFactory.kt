package com.doner.app

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/** Renders AdMob native ads for the directory lists. The template is
 *  visually an ad (red headline + advertiser label) and never mimics
 *  a donor entry. */
class DonerNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_layout, null) as NativeAdView

        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        if (nativeAd.body == null) {
            bodyView.visibility = View.INVISIBLE
        } else {
            bodyView.text = nativeAd.body
        }
        adView.bodyView = bodyView

        val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)
        if (nativeAd.callToAction == null) {
            ctaView.visibility = View.INVISIBLE
        } else {
            ctaView.text = nativeAd.callToAction
        }
        adView.callToActionView = ctaView

        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        if (nativeAd.icon == null) {
            iconView.visibility = View.GONE
        } else {
            iconView.setImageDrawable(nativeAd.icon?.drawable)
        }
        adView.iconView = iconView

        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        advertiserView.text = nativeAd.advertiser ?: "Ad"
        adView.advertiserView = advertiserView

        adView.setNativeAd(nativeAd)
        return adView
    }
}
