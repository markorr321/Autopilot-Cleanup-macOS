function Show-DeviceSelectionGrid {
    param (
        [Parameter(Mandatory)]
        [array]$Devices,
        [string]$Title = "Select Devices to Remove from All Services"
    )

    if (-not ('GliderUI.Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader' -as [type])) {
        Remove-Module GliderUI -Force -ErrorAction SilentlyContinue
        Import-Module GliderUI -Force -ErrorAction Stop

        if (-not ('GliderUI.Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader' -as [type])) {
            $gliderModule = Get-Module GliderUI
            $gliderDll = if ($gliderModule) {
                Join-Path $gliderModule.ModuleBase "bin/net8.0/GliderUI.dll"
            }

            if ($gliderDll -and (Test-Path $gliderDll)) {
                Add-Type -Path $gliderDll -ErrorAction Stop
            } else {
                throw "GliderUI types could not be loaded. Reinstall GliderUI and try again."
            }
        }
    }

    $colors = @{
        WindowBackground      = "#111827"
        ControlBackground     = "#1F2937"
        ControlBackgroundHover = "#374151"
        ListBackground        = "#0F172A"
        ListItemHover         = "#1E293B"
        TextPrimary           = "#F9FAFB"
        TextSecondary         = "#CBD5E1"
        TextPlaceholder       = "#94A3B8"
        Border                = "#334155"
        ButtonBackground      = "#1F2937"
        ButtonHover           = "#374151"
        SelectedBackground    = "#0F766E"
        SelectedText          = "#F8FAFC"
        PrimaryAction         = "#0369A1"
        PrimaryActionBorder   = "#075985"
        SuccessAction         = "#15803D"
        SuccessActionBorder   = "#166534"
        WarningAction         = "#B91C1C"
        WarningActionBorder   = "#991B1B"
    }

    $script:cleanupSelectedDevices = @()
    $script:cleanupCurrentPage = 1
    $script:cleanupPageSize = 50
    $script:cleanupAllDeviceObjects = @()
    $script:cleanupFilteredDeviceObjects = @()
    $script:cleanupPageDeviceObjects = @()
    $script:cleanupSelectedDeviceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
    $xaml = @"
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle" Height="680" Width="1260"
        WindowStartupLocation="CenterScreen" Topmost="True"
        Background="$($colors.WindowBackground)">
    <Window.Styles>
        <Style Selector="Button">
            <Setter Property="Background" Value="$($colors.ButtonBackground)"/>
            <Setter Property="Foreground" Value="$($colors.TextPrimary)"/>
            <Setter Property="BorderBrush" Value="$($colors.Border)"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style Selector="Button:pointerover">
            <Setter Property="Background" Value="$($colors.ButtonHover)"/>
        </Style>
        <Style Selector="Button:disabled">
            <Setter Property="Background" Value="$($colors.ControlBackgroundHover)"/>
            <Setter Property="Foreground" Value="$($colors.TextPlaceholder)"/>
        </Style>
        <Style Selector="ListBoxItem">
            <Setter Property="Padding" Value="4,2"/>
        </Style>
        <Style Selector="ListBoxItem:pointerover">
            <Setter Property="Background" Value="$($colors.ListItemHover)"/>
        </Style>
        <Style Selector="ListBoxItem:selected">
            <Setter Property="Background" Value="$($colors.SelectedBackground)"/>
            <Setter Property="Foreground" Value="$($colors.SelectedText)"/>
        </Style>
    </Window.Styles>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="$escapedTitle"
                   FontSize="18" FontWeight="Bold" Foreground="$($colors.TextPrimary)"
                   Margin="0,0,0,10"/>

        <TextBox x:Name="SearchBox" Grid.Row="1" Margin="0,0,0,10" Padding="8"
                 FontSize="14" Watermark="Search devices..."
                 Background="$($colors.ControlBackground)" Foreground="$($colors.TextPrimary)"
                 BorderBrush="$($colors.Border)"/>

        <TextBlock x:Name="ColumnHeader" Grid.Row="2" Margin="5,0,0,5"
                   FontFamily="Cascadia Mono,Consolas,Menlo,monospace"
                   FontSize="13" FontWeight="Bold" Foreground="$($colors.TextSecondary)"/>

        <ListBox x:Name="DeviceList" Grid.Row="3"
                 Background="$($colors.ListBackground)" Foreground="$($colors.TextPrimary)"
                 BorderBrush="$($colors.Border)" BorderThickness="1"
                 FontFamily="Cascadia Mono,Consolas,Menlo,monospace" FontSize="13"/>

        <Grid Grid.Row="4" Margin="0,10,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="SelectionCount" Grid.Column="0"
                       Text="0 devices selected" VerticalAlignment="Center"
                       FontWeight="Bold" FontSize="13" Foreground="$($colors.TextPrimary)"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" Spacing="4">
                <Button x:Name="FirstPageBtn" Content="First" Width="70" FontSize="12"/>
                <Button x:Name="PrevPageBtn" Content="Prev" Width="70" FontSize="12"/>
                <TextBlock x:Name="PageInfo" Text="Page 1 of 1" VerticalAlignment="Center"
                           Margin="10,0" FontSize="13" FontWeight="SemiBold"
                           Foreground="$($colors.TextPrimary)"/>
                <Button x:Name="NextPageBtn" Content="Next" Width="70" FontSize="12"/>
                <Button x:Name="LastPageBtn" Content="Last" Width="70" FontSize="12"/>
            </StackPanel>
            <TextBlock x:Name="TotalDevices" Grid.Column="2" Text="Total: 0 devices"
                       VerticalAlignment="Center" HorizontalAlignment="Right"
                       FontSize="13" Foreground="$($colors.TextPrimary)"/>
        </Grid>

        <Grid Grid.Row="5" Margin="0,5,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0" Orientation="Horizontal" Spacing="8">
                <Button x:Name="SelectAllFilteredBtn" Content="Select Filtered" Width="140"
                        Background="$($colors.SuccessAction)" Foreground="White" BorderBrush="$($colors.SuccessActionBorder)"/>
                <Button x:Name="SelectPageBtn" Content="Select Page" Width="120"/>
                <Button x:Name="ClearSelectionBtn" Content="Clear Selection" Width="130"/>
            </StackPanel>

            <StackPanel Grid.Column="1" Orientation="Horizontal" Spacing="8">
                <Button x:Name="CancelBtn" Content="Cancel" Width="100"/>
                <Button x:Name="ConfirmBtn" Content="OK" Width="100" FontSize="14" IsEnabled="False"
                        Background="$($colors.PrimaryAction)" Foreground="White" BorderBrush="$($colors.PrimaryActionBorder)" FontWeight="Bold"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $window = [GliderUI.Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse($xaml, $null)

    $searchBox = $window.FindControl("SearchBox")
    $columnHeader = $window.FindControl("ColumnHeader")
    $deviceList = $window.FindControl("DeviceList")
    $pageInfo = $window.FindControl("PageInfo")
    $firstPageBtn = $window.FindControl("FirstPageBtn")
    $prevPageBtn = $window.FindControl("PrevPageBtn")
    $nextPageBtn = $window.FindControl("NextPageBtn")
    $lastPageBtn = $window.FindControl("LastPageBtn")
    $selectAllFilteredBtn = $window.FindControl("SelectAllFilteredBtn")
    $selectPageBtn = $window.FindControl("SelectPageBtn")
    $clearSelectionBtn = $window.FindControl("ClearSelectionBtn")
    $cancelBtn = $window.FindControl("CancelBtn")
    $confirmBtn = $window.FindControl("ConfirmBtn")
    $selectionCount = $window.FindControl("SelectionCount")
    $totalDevices = $window.FindControl("TotalDevices")

    $columnHeader.Text = " {0,-3} {1,-28} {2,-22} {3,-20} {4,-12} {5,-7} {6}" -f "Sel", "Display Name", "Serial Number", "Model", "Group Tag", "Intune", "Entra"

    for ($index = 0; $index -lt $Devices.Count; $index++) {
        $device = $Devices[$index]
        $deviceId = if ($device.AutopilotId) {
            [string]$device.AutopilotId
        } elseif ($device.SerialNumber) {
            [string]$device.SerialNumber
        } else {
            "device-$index"
        }

        $script:cleanupAllDeviceObjects += [PSCustomObject]@{
            Id           = $deviceId
            DisplayName  = [string]$device.DisplayName
            SerialNumber = [string]$device.SerialNumber
            Model        = [string]$device.Model
            GroupTag     = [string]$device.GroupTag
            IntuneFound  = [string]$device.IntuneFound
            EntraFound   = [string]$device.EntraFound
            Original     = $device
        }
    }

    $script:cleanupFilteredDeviceObjects = @($script:cleanupAllDeviceObjects)

    $formatDeviceRow = {
        param($Device, [bool]$IsSelected)

        $check = if ($IsSelected) { "☑" } else { "☐" }
        $name = if ($Device.DisplayName.Length -gt 28) { $Device.DisplayName.Substring(0, 25) + "..." } else { $Device.DisplayName }
        $serial = if ($Device.SerialNumber.Length -gt 22) { $Device.SerialNumber.Substring(0, 19) + "..." } else { $Device.SerialNumber }
        $model = if ($Device.Model.Length -gt 20) { $Device.Model.Substring(0, 17) + "..." } else { $Device.Model }
        $groupTag = if ($Device.GroupTag.Length -gt 12) { $Device.GroupTag.Substring(0, 9) + "..." } else { $Device.GroupTag }
        return " {0}   {1,-28} {2,-22} {3,-20} {4,-12} {5,-7} {6}" -f $check, $name, $serial, $model, $groupTag, $Device.IntuneFound, $Device.EntraFound
    }

    $updateDeviceListUI = {
        $totalPages = [Math]::Max(1, [Math]::Ceiling($script:cleanupFilteredDeviceObjects.Count / $script:cleanupPageSize))
        $script:cleanupCurrentPage = [Math]::Min($script:cleanupCurrentPage, $totalPages)
        $script:cleanupCurrentPage = [Math]::Max(1, $script:cleanupCurrentPage)

        $startIndex = ($script:cleanupCurrentPage - 1) * $script:cleanupPageSize
        $script:cleanupPageDeviceObjects = @($script:cleanupFilteredDeviceObjects | Select-Object -Skip $startIndex -First $script:cleanupPageSize)

        $list = [GliderUI.System.Collections.ObjectModel.ObservableCollection[string]]::new()
        foreach ($device in $script:cleanupPageDeviceObjects) {
            $isSelected = $script:cleanupSelectedDeviceIds.Contains($device.Id)
            $null = $list.Add((& $formatDeviceRow $device $isSelected))
        }
        $deviceList.ItemsSource = $list

        $pageInfo.Text = "Page $($script:cleanupCurrentPage) of $totalPages"
        $totalDevices.Text = "Total: $($script:cleanupFilteredDeviceObjects.Count) devices"

        $firstPageBtn.IsEnabled = $script:cleanupCurrentPage -gt 1
        $prevPageBtn.IsEnabled = $script:cleanupCurrentPage -gt 1
        $nextPageBtn.IsEnabled = $script:cleanupCurrentPage -lt $totalPages
        $lastPageBtn.IsEnabled = $script:cleanupCurrentPage -lt $totalPages
    }

    $updateSelectionCountUI = {
        $count = $script:cleanupSelectedDeviceIds.Count
        $selectionCount.Text = "$count device$(if ($count -ne 1) { 's' }) selected"
        $confirmBtn.IsEnabled = $count -gt 0
    }

    $applyDeviceFilter = {
        $filterText = if ($searchBox.Text) { $searchBox.Text.Trim().ToLowerInvariant() } else { "" }
        if ([string]::IsNullOrEmpty($filterText)) {
            $script:cleanupFilteredDeviceObjects = @($script:cleanupAllDeviceObjects)
        } else {
            $script:cleanupFilteredDeviceObjects = @(
                $script:cleanupAllDeviceObjects | Where-Object {
                    $_.DisplayName.ToLowerInvariant().Contains($filterText) -or
                    $_.SerialNumber.ToLowerInvariant().Contains($filterText) -or
                    $_.Model.ToLowerInvariant().Contains($filterText) -or
                    $_.GroupTag.ToLowerInvariant().Contains($filterText)
                }
            )
        }

        $script:cleanupCurrentPage = 1
        & $updateDeviceListUI
    }

    $deviceList.AddSelectionChanged({
        $selectedIndex = $deviceList.SelectedIndex
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $script:cleanupPageDeviceObjects.Count) {
            $deviceId = $script:cleanupPageDeviceObjects[$selectedIndex].Id
            if ($script:cleanupSelectedDeviceIds.Contains($deviceId)) {
                [void]$script:cleanupSelectedDeviceIds.Remove($deviceId)
            } else {
                [void]$script:cleanupSelectedDeviceIds.Add($deviceId)
            }

            & $updateDeviceListUI
            & $updateSelectionCountUI
        }
    })

    $searchBox.AddTextChanged({ & $applyDeviceFilter })

    $firstPageBtn.AddClick({
        $script:cleanupCurrentPage = 1
        & $updateDeviceListUI
    })

    $prevPageBtn.AddClick({
        if ($script:cleanupCurrentPage -gt 1) {
            $script:cleanupCurrentPage--
            & $updateDeviceListUI
        }
    })

    $nextPageBtn.AddClick({
        $totalPages = [Math]::Ceiling($script:cleanupFilteredDeviceObjects.Count / $script:cleanupPageSize)
        if ($script:cleanupCurrentPage -lt $totalPages) {
            $script:cleanupCurrentPage++
            & $updateDeviceListUI
        }
    })

    $lastPageBtn.AddClick({
        $script:cleanupCurrentPage = [Math]::Max(1, [Math]::Ceiling($script:cleanupFilteredDeviceObjects.Count / $script:cleanupPageSize))
        & $updateDeviceListUI
    })

    $selectAllFilteredBtn.AddClick({
        foreach ($device in $script:cleanupFilteredDeviceObjects) {
            [void]$script:cleanupSelectedDeviceIds.Add($device.Id)
        }
        & $updateDeviceListUI
        & $updateSelectionCountUI
    })

    $selectPageBtn.AddClick({
        foreach ($device in $script:cleanupPageDeviceObjects) {
            [void]$script:cleanupSelectedDeviceIds.Add($device.Id)
        }
        & $updateDeviceListUI
        & $updateSelectionCountUI
    })

    $clearSelectionBtn.AddClick({
        $script:cleanupSelectedDeviceIds.Clear()
        & $updateDeviceListUI
        & $updateSelectionCountUI
    })

    $cancelBtn.AddClick({
        $script:cleanupSelectedDevices = @()
        $window.Close()
    })

    $confirmBtn.AddClick({
        $script:cleanupSelectedDevices = @(
            $script:cleanupAllDeviceObjects |
                Where-Object { $script:cleanupSelectedDeviceIds.Contains($_.Id) } |
                ForEach-Object { $_.Original }
        )
        $window.Close()
    })

    $window.AddKeyDown({
        param($handler, $sender, $e)
        if ($e.Key.ToString() -eq "Escape") {
            $script:cleanupSelectedDevices = @()
            $window.Close()
        }
    })

    & $updateDeviceListUI
    & $updateSelectionCountUI

    $window.Show()
    $window.WaitForClosed()

    if ($script:cleanupSelectedDevices.Count -gt 0) {
        return $script:cleanupSelectedDevices
    }

    return $null
}
